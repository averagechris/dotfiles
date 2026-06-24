#!/usr/bin/env bash
# Check the opencode upstream patches for staleness.
#
# Each patch in flakes/hm-modules/modules/opencode/patches/ is dry-run against
# the *locked* upstream opencode source tree and classified:
#
#   needed  - applies forward cleanly (still doing work)
#   stale   - already applied upstream (reverse applies cleanly); the patch is
#             no longer needed and should be removed
#   broken  - neither forward nor reverse applies; upstream diverged and the
#             patch must be updated
#
# Exit status is non-zero if any patch is `stale` or `broken`, so this can be
# wired into CI or run after bumping the opencode flake input.
#
# Usage:
#   scripts/check-opencode-patches.sh [--source PATH]
#
#   --source PATH   Use this upstream opencode source tree instead of
#                   resolving the locked flake input (useful for offline runs
#                   or testing a candidate bump before locking it).
#   -h, --help      Show this help.
set -euo pipefail

color_red=$'\033[31m'
color_yellow=$'\033[33m'
color_green=$'\033[32m'
color_dim=$'\033[2m'
color_reset=$'\033[0m'
no_color=0
if [[ ! -t 1 ]]; then no_color=1; fi
c() { if ((no_color)); then printf '%s' "$2"; else printf '%s%s%s' "$1" "$2" "$color_reset"; fi; }

usage() {
  sed -n '2,/^# Usage:/p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

repo_root() {
  if command -v jj >/dev/null 2>&1; then
    jj root 2>/dev/null && return
  fi
  git rev-parse --show-toplevel 2>/dev/null && return
  echo "Could not determine repository root" >&2
  exit 1
}

PATCHES_DIR=""
SOURCE_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) SOURCE_OVERRIDE="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

ROOT="$(repo_root)"
PATCHES_DIR="$ROOT/flakes/hm-modules/modules/opencode/patches"

if [[ ! -d "$PATCHES_DIR" ]]; then
  echo "Patches directory not found: $PATCHES_DIR" >&2
  exit 2
fi

shopt -s nullglob
patches=("$PATCHES_DIR"/*.patch)
shopt -u nullglob
if [[ ${#patches[@]} -eq 0 ]]; then
  echo "No patches found in $PATCHES_DIR"
  exit 0
fi

# Resolve the locked upstream opencode source tree.
if [[ -n "$SOURCE_OVERRIDE" ]]; then
  src="$SOURCE_OVERRIDE"
  rev="(provided)"
else
  lock="$ROOT/flakes/hm-modules/flake.lock"
  if [[ ! -f "$lock" ]]; then
    echo "flake.lock not found: $lock" >&2
    exit 2
  fi
  # Find the opencode input node (the one whose original.repo == "opencode").
  read -r ref rev <<<"$(python3 - "$lock" <<'PY'
import json, sys
lock = json.load(open(sys.argv[1]))
nodes = lock.get("nodes", {})
for name, node in nodes.items():
    orig = node.get("original", {})
    if orig.get("repo") == "opencode" and orig.get("type") == "github":
        locked = node.get("locked", {})
        owner = locked.get("owner", orig.get("owner", ""))
        repo = locked.get("repo", "opencode")
        rev = locked.get("rev", "")
        if rev:
            print(f"github:{owner}/{repo}/{rev} {rev}")
            break
PY
)"
  if [[ -z "$ref" ]]; then
    echo "Could not find locked opencode input in $lock" >&2
    exit 2
  fi
  echo "Resolving upstream opencode source: $ref" >&2
  src="$(nix flake metadata "$ref" --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["path"])')"
  if [[ -z "$src" || ! -d "$src" ]]; then
    echo "Could not resolve upstream opencode source path" >&2
    exit 2
  fi
fi

echo "Upstream source: $src (rev $rev)"
echo "Checking ${#patches[@]} patch(es) in flakes/hm-modules/modules/opencode/patches/"
echo

stale=0
broken=0
needed=0

for patch in "${patches[@]}"; do
  name="$(basename "$patch")"
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  cp -R "$src/." "$work/"
  chmod -R u+w "$work/" 2>/dev/null || true

  set +e
  patch -p1 --dry-run --forward --force -d "$work" < "$patch" >/dev/null 2>&1
  fwd_rc=$?
  patch -p1 --dry-run --reverse --force -d "$work" < "$patch" >/dev/null 2>&1
  rev_rc=$?
  set -e

  if [[ $fwd_rc -eq 0 ]]; then
    c "$color_green" "needed"; printf '  %s\n' "$name"
    needed=$((needed + 1))
  elif [[ $rev_rc -eq 0 ]]; then
    c "$color_yellow" "stale "; printf '  %s\n' "$name"
    printf '         %supstream already includes this patch; remove it%s\n' "$color_dim" "$color_reset"
    stale=$((stale + 1))
  else
    c "$color_red" "broken"; printf '  %s\n' "$name"
    printf '         %supstream diverged; update or remove this patch%s\n' "$color_dim" "$color_reset"
    broken=$((broken + 1))
  fi
  rm -rf "$work"
  trap - EXIT
done

echo
echo "Summary: $needed needed, $stale stale, $broken broken"

if [[ $stale -gt 0 || $broken -gt 0 ]]; then
  exit 1
fi
exit 0