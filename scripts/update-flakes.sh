#!/usr/bin/env bash
# Update all flake.lock files in the repository
#
# This script updates the top-level flake and all host flakes.
# Run it periodically to keep dependencies up to date.
#
# Usage:
#   ./scripts/update-flakes.sh           # Update all flakes
#   ./scripts/update-flakes.sh --check   # Check for updates without applying

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_only=false
if [[ "${1:-}" == "--check" ]]; then
    check_only=true
fi

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

update_flake() {
    local flake_path="$1"
    local flake_name="$2"
    
    if [[ ! -f "$flake_path/flake.nix" ]]; then
        log_warn "Skipping $flake_name: no flake.nix found"
        return
    fi
    
    log_info "Updating $flake_name..."
    
    if $check_only; then
        # Just check if there are updates available
        if nix flake update --flake "$flake_path" --dry-run 2>&1 | grep -q "would update"; then
            log_info "  Updates available for $flake_name"
        else
            log_info "  $flake_name is up to date"
        fi
    else
        nix flake update --flake "$flake_path"
    fi
}

cd "$REPO_ROOT"

log_info "Starting flake updates..."
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
fi
