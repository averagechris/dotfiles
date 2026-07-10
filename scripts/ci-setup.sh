#!/usr/bin/env bash
# CI setup script for SourceHut builds
# Configures Nix experimental features and cachix

set -euo pipefail

report_nix_setting() {
  local key="$1"
  local value=""

  if value="$(nix config show "$key" 2>/dev/null)"; then
    printf '%s = %s\n' "$key" "$value"
    return
  fi

  if value="$(nix show-config "$key" 2>/dev/null)"; then
    printf '%s = %s\n' "$key" "$value"
    return
  fi

  printf '%s = <unavailable>\n' "$key"
}

report_ci_nix_environment() {
  printf '== ci nix environment ==\n'
  printf 'revision = '
  if command -v git >/dev/null 2>&1 && git -C "${1:-.}" rev-parse --short HEAD >/dev/null 2>&1; then
    git -C "${1:-.}" rev-parse --short HEAD
  else
    printf '<unavailable>\n'
  fi
  printf 'system = '
  nix eval --raw --impure --expr builtins.currentSystem 2>/dev/null || printf '<unavailable>'
  printf '\n'
  printf 'nix_version = '
  nix --version 2>/dev/null || printf '<unavailable>\n'

  for key in \
    substituters \
    trusted-public-keys \
    builders \
    builders-use-substitutes \
    max-jobs \
    cores; do
    report_nix_setting "$key"
  done
}

# Configure Nix
mkdir -p ~/.config/nix/
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
echo "max-jobs = auto" >> ~/.config/nix/nix.conf

# Setup cachix
cachix authtoken --stdin < ~/.ci_secrets/cachix_token
cachix use averagechris-dotfiles

report_ci_nix_environment "${CI_REPO_PATH:-$HOME/dotfiles}"
