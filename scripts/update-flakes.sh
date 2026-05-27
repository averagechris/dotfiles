#!/usr/bin/env bash
# Update all flake.lock files in the repository
#
# This script updates the top-level flake and all host flakes.
# Run it periodically to keep dependencies up to date.
#
# Usage:
#   ./scripts/update-flakes.sh           # Update all flakes
#   ./scripts/update-flakes.sh --check   # Check for updates without applying
#   ./scripts/update-flakes.sh --ignore-cooldown

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_only=false
ignore_cooldown=false
cooldown_days="${FLAKE_UPDATE_COOLDOWN_DAYS:-7}"
cooldown_inputs="${FLAKE_UPDATE_COOLDOWN_INPUTS:-opencode,pi,pi-coding-agent}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)
            check_only=true
            shift
            ;;
        --ignore-cooldown)
            ignore_cooldown=true
            shift
            ;;
        --cooldown-days)
            cooldown_days="${2:?--cooldown-days requires a day count}"
            shift 2
            ;;
        --cooldown-inputs)
            cooldown_inputs="${2:?--cooldown-inputs requires a comma-separated input list}"
            shift 2
            ;;
        *)
            log_error "Unknown argument: $1"
            exit 2
            ;;
    esac
done

is_cooldown_input() {
    local input_name="$1"
    local input

    IFS=',' read -ra inputs <<< "$cooldown_inputs"
    for input in "${inputs[@]}"; do
        if [[ "$input" == "$input_name" ]]; then
            return 0
        fi
    done

    return 1
}

list_updateable_inputs() {
    local flake_path="$1"

    if [[ ! -f "$flake_path/flake.lock" ]]; then
        return 0
    fi

    python3 - "$flake_path/flake.lock" <<'PY'
import json
import sys

lock = json.load(open(sys.argv[1]))
nodes = lock.get("nodes", {})
root_inputs = nodes.get("root", {}).get("inputs", {})

for name, node_ref in root_inputs.items():
    # Followed inputs are updated through their source input.
    if not isinstance(node_ref, str):
        continue

    node = nodes.get(node_ref, {})
    locked = node.get("locked", {})
    original = node.get("original", {})
    input_type = original.get("type") or locked.get("type")

    # Local path flakes are refreshed by updating the flake that owns them; they
    # do not need a registry/network update of their own.
    if input_type == "path":
        continue

    print(name)
PY
}

input_ref_from_lock() {
    local flake_path="$1"
    local input_name="$2"

    python3 - "$flake_path/flake.lock" "$input_name" <<'PY'
import json
import sys

lock = json.load(open(sys.argv[1]))
input_name = sys.argv[2]
nodes = lock.get("nodes", {})
node_ref = nodes.get("root", {}).get("inputs", {}).get(input_name)

if not isinstance(node_ref, str):
    sys.exit(1)

node = nodes.get(node_ref, {})
original = node.get("original") or node.get("locked") or {}
input_type = original.get("type")

if input_type == "github":
    ref = f"github:{original['owner']}/{original['repo']}"
    if original.get("ref"):
        ref += f"/{original['ref']}"
    print(ref)
elif input_type == "sourcehut":
    ref = f"sourcehut:{original['owner']}/{original['repo']}"
    if original.get("ref"):
        ref += f"/{original['ref']}"
    print(ref)
elif input_type == "git":
    ref = f"git+{original['url']}"
    if original.get("ref"):
        ref += f"?ref={original['ref']}"
    print(ref)
else:
    sys.exit(1)
PY
}

candidate_last_modified() {
    local input_ref="$1"

    nix flake metadata --json "$input_ref" \
        | python3 -c 'import json, sys; print(json.load(sys.stdin)["locked"]["lastModified"])'
}

input_passes_cooldown() {
    local flake_name="$1"
    local flake_path="$2"
    local input_name="$3"
    local input_ref
    local last_modified
    local now
    local age_seconds
    local cooldown_seconds
    local age_days

    input_ref="$(input_ref_from_lock "$flake_path" "$input_name" 2>/dev/null || true)"
    if [[ -z "$input_ref" ]]; then
        log_warn "  Skipping $flake_name input '$input_name': cannot determine candidate ref for cooldown check"
        return 1
    fi

    if ! last_modified="$(candidate_last_modified "$input_ref" 2>/dev/null)"; then
        log_warn "  Skipping $flake_name input '$input_name': cannot determine candidate age for $input_ref"
        return 1
    fi

    now="$(date +%s)"
    age_seconds=$((now - last_modified))
    cooldown_seconds=$((cooldown_days * 24 * 60 * 60))
    age_days=$((age_seconds / 86400))

    if ((age_seconds < cooldown_seconds)); then
        log_warn "  Skipping $flake_name input '$input_name': latest $input_ref is ${age_days}d old; cooldown is ${cooldown_days}d"
        return 1
    fi

    return 0
}

update_flake() {
    local flake_path="$1"
    local flake_name="$2"
    local input
    local has_cooldown_input=false
    local update_inputs=()
    
    if [[ ! -f "$flake_path/flake.nix" ]]; then
        log_warn "Skipping $flake_name: no flake.nix found"
        return
    fi
    
    log_info "Updating $flake_name..."

    if ! $ignore_cooldown && [[ -f "$flake_path/flake.lock" ]]; then
        while IFS= read -r input; do
            if is_cooldown_input "$input"; then
                has_cooldown_input=true
                if input_passes_cooldown "$flake_name" "$flake_path" "$input"; then
                    update_inputs+=("$input")
                fi
            else
                update_inputs+=("$input")
            fi
        done < <(list_updateable_inputs "$flake_path")

        # Keep the historical all-input update path unless this flake actually
        # contains a cooled input. This still refreshes path inputs in the
        # top-level aggregator flake and any flakes without supply-chain gates.
        if ! $has_cooldown_input; then
            update_inputs=()
        elif [[ ${#update_inputs[@]} -eq 0 ]]; then
            log_info "  No updateable inputs remain for $flake_name after cooldown checks"
            return
        fi
    fi
    
    if $check_only; then
        # Just check if there are updates available
        if $ignore_cooldown || [[ ${#update_inputs[@]} -eq 0 ]]; then
            if nix flake update --flake "$flake_path" --dry-run 2>&1 | grep -q "would update"; then
                log_info "  Updates available for $flake_name"
            else
                log_info "  $flake_name is up to date"
            fi
        elif nix flake update "${update_inputs[@]}" --flake "$flake_path" --dry-run 2>&1 | grep -q "would update"; then
            log_info "  Updates available for $flake_name"
        else
            log_info "  $flake_name is up to date"
        fi
    else
        if $ignore_cooldown || [[ ${#update_inputs[@]} -eq 0 ]]; then
            nix flake update --flake "$flake_path"
        else
            nix flake update "${update_inputs[@]}" --flake "$flake_path"
        fi
    fi
}

cd "$REPO_ROOT"

log_info "Starting flake updates..."
if ! $ignore_cooldown; then
    log_info "Cooldown: ${cooldown_days}d for inputs: ${cooldown_inputs}"
else
    log_warn "Cooldown checks are disabled for this run"
fi
echo ""

# Update shared module flakes first (they're dependencies)
log_info "=== Updating shared module flakes ==="
update_flake "$REPO_ROOT/flakes/base-lib" "base-lib"
update_flake "$REPO_ROOT/flakes/nixos-modules" "nixos-modules"
update_flake "$REPO_ROOT/flakes/hm-modules" "hm-modules"
update_flake "$REPO_ROOT/flakes/darwin-modules" "darwin-modules"
echo ""

# Update host flakes
log_info "=== Updating host flakes ==="
for host_dir in "$REPO_ROOT"/flakes/hosts/*/; do
    host_name=$(basename "$host_dir")
    update_flake "$host_dir" "hosts/$host_name"
done
echo ""

# Update top-level flake last
log_info "=== Updating top-level flake ==="
update_flake "$REPO_ROOT" "top-level"
echo ""

if $check_only; then
    log_info "Check complete. Run without --check to apply updates."
else
    log_info "All flakes updated successfully!"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Review changes: jj diff"
    log_info "  2. Test builds: nix flake check"
    log_info "  3. Commit: jj describe -m 'chore: update flake.lock files'"
    log_info ""
    log_info "Use --ignore-cooldown only after manually reviewing fresh upstream releases."
fi
