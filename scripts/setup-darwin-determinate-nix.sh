#!/usr/bin/env bash
# Configure Nix daemon on macOS (Determinate Nix) with the desired substituters,
# public keys, and performance settings for this machine. This script writes to
# /etc/nix/nix.custom.conf (the only supported customization channel for
# Determinate Nix) and is idempotent and safe to re-run.
#
# Desired caches for suremac:
# - https://cache.nixos.org (official)
# - https://nix-community.cachix.org
# - https://averagechris-dotfiles.cachix.org
# - https://devenv.cachix.org
# - https://helix.cachix.org
#
# Performance settings for suremac:
# - fsync-metadata = false: on macOS, Nix's metadata flush uses F_FULLFSYNC,
#   which is very slow on APFS and makes every /nix/var/nix/db/db.sqlite write
#   transaction hold the lock long enough that parallel agents/builds pile up
#   with "SQLite database is busy" warnings. Disabling it dramatically shortens
#   lock hold times. Trade-off: a *system* crash (kernel panic/power loss) can
#   lose the most recent DB registrations; recover with
#   `nix store verify --repair` or by re-substituting. See docs/suremac.md.
#
# Usage:
#   nix run .#setup-darwin-determinate-substituters
# or directly:
#   ./scripts/setup-darwin-determinate-nix.sh
#
# Verify after running:
#   nix config show | rg '^(substituters|trusted-public-keys|trusted-users|fsync-metadata)'

set -euo pipefail

if [[ "${OSTYPE:-}" != darwin* ]]; then
  echo "This script is intended for macOS (Darwin)." >&2
  exit 1
fi

if ! command -v nix >/dev/null 2>&1; then
  echo "nix not found. Please install Determinate Nix first: https://determinate.systems/nix" >&2
  exit 1
fi

# Desired substituters and keys (explicitly include cache.nixos.org)
SUBS=(
  "https://cache.nixos.org/"
  "https://nix-community.cachix.org"
  "https://averagechris-dotfiles.cachix.org"
  "https://devenv.cachix.org"
  "https://helix.cachix.org"
)
KEYS=(
  # Explicitly include the cache.nixos.org key: newer Determinate Nix versions
  # treat a trusted-public-keys line in nix.custom.conf as a full replacement
  # (observed on Determinate Nix 3.21), which silently drops the default key
  # and causes full from-source rebuilds.
  "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
  "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  "averagechris-dotfiles.cachix.org-1:VwJkl5dG1+xGDY5x884mH/kVwwpgwBAdBKIF3BZiia4="
  "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
  "helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs="
)

CUR_USER=$(id -un)
TRUSTED_USERS=(root "$CUR_USER")

join() { local IFS=" "; echo "$*"; }
SUBS_STR=$(join "${SUBS[@]}")
KEYS_STR=$(join "${KEYS[@]}")
USERS_STR=$(join "${TRUSTED_USERS[@]}")

# Elevate once and perform all privileged operations in a single subshell
sudo env SUBS_STR="$SUBS_STR" KEYS_STR="$KEYS_STR" USERS_STR="$USERS_STR" bash <<'ROOT'
set -euo pipefail
NIX_DIR=/etc/nix
NIX_CUSTOM=$NIX_DIR/nix.custom.conf
TMP_CONF=$(mktemp)
trap 'rm -f "$TMP_CONF"' EXIT
mkdir -p "$NIX_DIR"
if [[ -f "$NIX_CUSTOM" ]]; then
  # Remove existing lines for the settings we manage to avoid duplicates
  awk 'BEGIN{IGNORECASE=1} !($0 ~ /^(substituters|trusted-public-keys|trusted-users|fsync-metadata)[[:space:]]*=/) {print}' "$NIX_CUSTOM" > "$TMP_CONF"
else
  : > "$TMP_CONF"
fi
{
  echo "# Managed by setup-darwin-determinate-nix.sh"
  echo "# See https://docs.determinate.systems/determinate-nix for details"
  cat "$TMP_CONF"
  echo "substituters = ${SUBS_STR}"
  echo "trusted-public-keys = ${KEYS_STR}"
  echo "trusted-users = ${USERS_STR}"
  echo "# Avoid F_FULLFSYNC per nix-db write on APFS; reduces SQLite lock"
  echo "# contention under parallel agents. See docs/suremac.md."
  echo "fsync-metadata = false"
} > "$NIX_CUSTOM"
# Restart the daemon so daemon-side settings (fsync-metadata, trusted-users)
# take effect now. This also checkpoints and truncates the SQLite WAL file
# (/nix/var/nix/db/db.sqlite-wal), which can grow large under sustained
# parallel load. Substituter settings alone would not need this.
launchctl kickstart -k system/systems.determinate.nix-daemon
ROOT

echo
echo "Effective settings (filtered):"
# grep, not rg: this runs on freshly bootstrapped machines with no tools yet
nix config show | grep -E '^(substituters|trusted-public-keys|trusted-users|fsync-metadata)'

echo
echo "Done. Substituters are trusted and nix-db writes skip F_FULLFSYNC."
