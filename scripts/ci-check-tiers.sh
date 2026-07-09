#!/usr/bin/env bash
# Shared SourceHut CI check tiers for this repository.

set -euo pipefail

tier="${1:-}"

x86_hosts=(trap thorny tom cruber tater)
shared_flakes=(base-lib nixos-modules hm-modules darwin-modules)
explicit_checks=(
  ".#checks.x86_64-linux.tater-desktop-static"
  ".#checks.x86_64-linux.tater-hyprland-greeter-config"
  ".#checks.x86_64-linux.tater-hyprland-home-config"
  ".#checks.x86_64-linux.thorny-hyprland-greeter-config"
  ".#checks.x86_64-linux.thorny-hyprland-home-config"
)

usage() {
  cat >&2 <<'EOF'
usage: scripts/ci-check-tiers.sh TIER

TIER:
  fast              format, statix, shellcheck, and shared flake eval-only checks
  x86-host-builds   build active x86_64 NixOS hosts sequentially, no result links
  trainwreck-build  build trainwreck natively on aarch64, no result link
  coverage-checks   suremac eval-only plus selected desktop check builds
  full-fleet        manual full root nix flake check with builds enabled
EOF
}

flake_check_no_build() {
  nix flake check --accept-flake-config --no-write-lock-file --no-build "$@"
}

shellcheck_repo_scripts() {
  local scripts=()
  local script

  if command -v jj >/dev/null 2>&1 && jj root >/dev/null 2>&1; then
    while IFS= read -r script; do
      [[ "$script" == *.sh ]] || continue
      scripts+=("$script")
    done < <(jj file list)
  else
    while IFS= read -r -d '' script; do
      scripts+=("$script")
    done < <(git ls-files -z -- '*.sh')
  fi

  if ((${#scripts[@]} == 0)); then
    echo "No tracked shell scripts found."
    return 0
  fi

  shellcheck "${scripts[@]}"
}

host_eval() {
  local host="$1"

  case "$host" in
    suremac)
      nix eval --raw --accept-flake-config --no-write-lock-file --option eval-cache false ".#darwinConfigurations.$host.system"
      ;;
    *)
      nix eval --raw --accept-flake-config --no-write-lock-file --option eval-cache false ".#nixosConfigurations.$host.config.system.build.toplevel.drvPath"
      ;;
  esac
}

require_system() {
  local expected="$1"
  local current_system

  current_system="$(nix eval --raw --impure --no-write-lock-file --expr 'builtins.currentSystem')"
  if [[ "$current_system" != "$expected" ]]; then
    echo "Skipping $tier on $current_system; expected $expected."
    exit 0
  fi
}

build_nixos_host() {
  local host="$1"
  local attr=".#nixosConfigurations.$host.config.system.build.toplevel"

  echo "==> Building NixOS host: $host"
  nix build --accept-flake-config --no-write-lock-file --no-link "$attr"
}

build_check() {
  local check="$1"

  echo "==> Building check: $check"
  nix build --accept-flake-config --no-write-lock-file --no-link "$check"
}

case "$tier" in
  fast)
    echo "==> Checking formatting"
    alejandra --check .
    echo "==> Running statix"
    statix check
    echo "==> Running shellcheck"
    shellcheck_repo_scripts
    for flake in "${shared_flakes[@]}"; do
      echo "==> Eval-only flake check: ./flakes/$flake"
      flake_check_no_build "./flakes/$flake"
    done
    ;;
  x86-host-builds)
    require_system x86_64-linux
    for host in "${x86_hosts[@]}"; do
      build_nixos_host "$host"
    done
    ;;
  trainwreck-build)
    require_system aarch64-linux
    build_nixos_host trainwreck
    ;;
  coverage-checks)
    require_system x86_64-linux
    echo "==> Evaluating suremac Darwin system (eval only)"
    host_eval suremac
    printf '\n'
    for check in "${explicit_checks[@]}"; do
      build_check "$check"
    done
    ;;
  full-fleet)
    nix flake check --accept-flake-config --no-write-lock-file
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage
    exit 64
    ;;
esac
