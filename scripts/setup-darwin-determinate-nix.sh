#!/usr/bin/env bash
# Configure Nix daemon on macOS (Determinate Nix) with the desired substituters
# and public keys for this machine. This script writes to /etc/nix/nix.custom.conf
# (as recommended by Determinate Nix) and restarts the nix-daemon.
# It is idempotent and safe to re-run.
#
# Desired caches for suremac:
# - https://cache.nixos.org (official)
# - https://nix-community.cachix.org
# - https://averagechris-dotfiles.cachix.org
# - https://devenv.cachix.org
# - https://helix.cachix.org
#
# Usage:
#   nix run .#setup-darwin-determinate-substituters
# or directly:
#   ./nixpkgs/scripts/setup-darwin-determinate-nix.sh
#
# Verify after running:
#   nix show-config | rg '^(substituters|trusted-public-keys|trusted-users)'

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
  awk 'BEGIN{IGNORECASE=1} !($0 ~ /^(substituters|trusted-public-keys|trusted-users)[[:space:]]*=/) {print}' "$NIX_CUSTOM" > "$TMP_CONF"
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
} > "$NIX_CUSTOM"
# Note: no need to restart the daemon explicitly; it will pick up changes
# from nix.custom.conf on next use or after any future daemon restart.
ROOT

echo
echo "Effective settings (filtered):"
# grep, not rg: this runs on freshly bootstrapped machines with no tools yet
nix config show | grep -E '^(substituters|trusted-public-keys|trusted-users)'

echo
echo "Done. You should no longer see untrusted substituter warnings."
