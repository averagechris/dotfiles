#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: dotfiles-maintenance-gate [OPTIONS]

Run the documented maintenance check gate and print per-step timings.

Options:
  --profile NAME   Gate profile: smoke, thorny, no-build, full (default: smoke)
  --repo PATH      Dotfiles checkout to check (default: DOTFILES_REPO_ROOT or cwd)
  --system SYSTEM  Nix system for package evals (default: builtins.currentSystem)
  --log-dir PATH   Capture each step's output in PATH
  --show-output    Stream step output while also writing logs
  --list-profiles  Print available profiles and exit
  -h, --help       Show this help

Profiles:
  smoke    Flake metadata plus top-level maintenance package evals.
  thorny   smoke plus thorny system derivation eval.
  no-build Top-level nix flake check --no-build.
  full     Top-level nix flake check with builds enabled.
USAGE
}

list_profiles() {
  cat <<'PROFILES'
smoke
thorny
no-build
full
PROFILES
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 2
}

profile=smoke
repo="${DOTFILES_REPO_ROOT:-$(pwd)}"
system="${DOTFILES_MAINTENANCE_GATE_SYSTEM:-}"
log_dir="${DOTFILES_MAINTENANCE_GATE_LOG_DIR:-}"
show_output=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile)
      [ "$#" -ge 2 ] || die "--profile requires a value"
      profile="$2"
      shift 2
      ;;
    --repo)
      [ "$#" -ge 2 ] || die "--repo requires a path"
      repo="$2"
      shift 2
      ;;
    --system)
      [ "$#" -ge 2 ] || die "--system requires a value"
      system="$2"
      shift 2
      ;;
    --log-dir)
      [ "$#" -ge 2 ] || die "--log-dir requires a path"
      log_dir="$2"
      shift 2
      ;;
    --show-output)
      show_output=true
      shift
      ;;
    --list-profiles)
      list_profiles
      exit 0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

case "$profile" in
  smoke|thorny|no-build|full) ;;
  *) die "unknown profile: $profile" ;;
esac

[ -d "$repo" ] || die "repo path does not exist: $repo"
repo=$(cd "$repo" && pwd -P)
[ -f "$repo/flake.nix" ] || die "repo path is missing flake.nix: $repo"

if [ -z "$log_dir" ]; then
  log_dir=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-maintenance-gate.XXXXXX")
fi

if [ -n "$log_dir" ]; then
  mkdir -p "$log_dir"
  log_dir=$(cd "$log_dir" && pwd -P)
fi

if [ -z "$system" ]; then
  system=$(nix eval --raw --impure --expr builtins.currentSystem)
fi

step_index=0
total_start=$(date +%s)

run_step() {
  local label="$1"
  shift
  local start end duration status slug log_file

  step_index=$((step_index + 1))
  slug=${label//[^[:alnum:]]/-}
  log_file=""
  if [ -n "$log_dir" ]; then
    printf -v log_file '%s/%02d-%s.log' "$log_dir" "$step_index" "$slug"
  fi

  printf '\n== %s ==\n' "$label"
  printf '+ '
  printf '%q ' "$@"
  printf '\n'
  if [ -n "$log_file" ]; then
    printf 'log: %s\n' "$log_file"
  fi

  start=$(date +%s)
  status=0
  if [ -n "$log_file" ] && [ "$show_output" = true ]; then
    "$@" 2>&1 | tee "$log_file" || status=${PIPESTATUS[0]}
  elif [ -n "$log_file" ]; then
    "$@" >"$log_file" 2>&1 || status=$?
  else
    "$@" || status=$?
  fi
  end=$(date +%s)
  duration=$((end - start))

  if [ "$status" -eq 0 ]; then
    printf 'ok: %s (%ss)\n' "$label" "$duration"
    return 0
  fi

  printf 'failed: %s (%ss, exit %s)\n' "$label" "$duration" "$status" >&2
  if [ -n "$log_file" ]; then
    printf 'see log: %s\n' "$log_file" >&2
  fi
  return "$status"
}

printf 'dotfiles maintenance gate\n'
printf 'repo: %s\n' "$repo"
printf 'profile: %s\n' "$profile"
printf 'system: %s\n' "$system"
if [ -n "$log_dir" ]; then
  printf 'log_dir: %s\n' "$log_dir"
fi

run_smoke() {
  run_step "flake metadata" \
    nix flake metadata --json --no-write-lock-file "$repo"
  run_step "update-flakes package eval" \
    nix eval --raw "$repo#packages.$system.update-flakes.name"
  run_step "maintenance gate package eval" \
    nix eval --raw "$repo#packages.$system.dotfiles-maintenance-gate.name"
}

case "$profile" in
  smoke)
    run_smoke
    ;;
  thorny)
    run_smoke
    run_step "thorny system derivation eval" \
      nix eval --raw "$repo#nixosConfigurations.thorny.config.system.build.toplevel.drvPath"
    ;;
  no-build)
    run_step "top-level flake check no-build" \
      nix flake check --accept-flake-config --no-build "$repo"
    ;;
  full)
    run_step "top-level flake check full" \
      nix flake check --accept-flake-config "$repo"
    ;;
esac

total_end=$(date +%s)
printf '\nmaintenance gate passed in %ss\n' "$((total_end - total_start))"
