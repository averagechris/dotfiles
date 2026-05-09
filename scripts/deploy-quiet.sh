#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: deploy-quiet [OPTIONS] HOST_OR_TARGET [-- DEPLOY_RS_ARGS...]

Quiet wrapper around this flake's deploy-rs app.

Examples:
  deploy-quiet trainwreck
  deploy-quiet .#trainwreck
  deploy-quiet --no-checks trainwreck
  deploy-quiet --deploy-rs-checks trainwreck
  deploy-quiet --show-output trainwreck
  deploy-quiet trainwreck -- --auto-rollback false

Options:
  --no-checks          Skip the host-specific pre-deploy flake check.
  --deploy-rs-checks   Let deploy-rs run its full flake checks instead of this
                       wrapper's host-specific check. This is noisier and checks
                       unrelated hosts on the top-level flake.
  --show-output        Stream check/deploy output live instead of only printing
                       it on failure.
  -h, --help           Show this help text.
EOF
}

run_host_check=true
run_deploy_rs_checks=false
show_output=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --checks)
      run_host_check=true
      shift
      ;;
    --no-checks)
      run_host_check=false
      shift
      ;;
    --deploy-rs-checks)
      run_host_check=false
      run_deploy_rs_checks=true
      shift
      ;;
    --show-output)
      show_output=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      printf 'deploy-quiet: unknown option: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 2
fi

target="$1"
shift

host="$target"
host="${host#.#}"
host="${host#\#}"
host="${host##*#}"

if [[ "$target" != .* && "$target" != *#* ]]; then
  target=".#$target"
fi

deploy_args=()
if [[ "$run_deploy_rs_checks" == false ]]; then
  deploy_args+=(--skip-checks)
fi
deploy_args+=("$target")
deploy_args+=("$@")

tmp_log="$(mktemp -t deploy-quiet.XXXXXX.log)"
trap 'rm -f "$tmp_log"' EXIT

run_buffered() {
  local label="$1"
  shift

  printf '%s... ' "$label"

  if [[ "$show_output" == true ]]; then
    printf '\n'
    "$@"
    return $?
  fi

  : >"$tmp_log"
  set +e
  "$@" >"$tmp_log" 2>&1
  local status=$?
  set -e

  if [[ $status -eq 0 ]]; then
    printf 'ok\n'
  else
    printf 'failed\n\n'
    cat "$tmp_log"
  fi

  return "$status"
}

if [[ "$run_host_check" == true ]]; then
  host_flake="./flakes/hosts/$host"
  if [[ -f "$host_flake/flake.nix" ]]; then
    run_buffered "Checking $host" nix --quiet flake check "$host_flake"
  else
    run_buffered "Checking $target" nix --quiet flake check "$target"
  fi
fi

deploy_label="Deploying $target"
if [[ "$run_deploy_rs_checks" == false ]]; then
  deploy_label="$deploy_label (deploy-rs checks skipped)"
fi

run_buffered "$deploy_label" nix --quiet run .#deploy -- "${deploy_args[@]}"
