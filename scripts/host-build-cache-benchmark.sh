#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: host-build-cache-benchmark --rev REV [--repo-url URL] [--runs N]

Compare the five x86_64-linux host installables used by thorny's
dotfiles-host-build-cache warmer as separate sequential Nix invocations versus
one multi-installable invocation at the same revision-pinned SourceHut flake URL.

This uses nix build --dry-run with the evaluation cache disabled, so it plans
builds/substitutions but does not realize closures or mutate result links. Runs
alternate which shape executes first to reduce systematic warm-cache bias.
trainwreck is intentionally excluded because its aarch64/QEMU behavior is a
separate bottleneck.
USAGE
}

die() { printf 'error: %s\n' "$*" >&2; exit 2; }

repo_url="https://git.sr.ht/~averagechris/dotfiles"
rev=""
runs=4

while [ "$#" -gt 0 ]; do
  case "$1" in
    --rev) [ "$#" -ge 2 ] || die "--rev requires a value"; rev=$2; shift 2 ;;
    --repo-url) [ "$#" -ge 2 ] || die "--repo-url requires a value"; repo_url=$2; shift 2 ;;
    --runs) [ "$#" -ge 2 ] || die "--runs requires a value"; runs=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ "$rev" =~ ^[0-9a-f]{40}$ ]] || die "--rev must be a 40-character lowercase git revision"
[[ "$runs" =~ ^[1-9][0-9]*$ ]] || die "--runs must be a positive integer"

flake_ref="git+$repo_url?rev=$rev"
hosts=(trap thorny tom cruber tater)
common_args=(--accept-flake-config --dry-run --no-link --no-write-lock-file --option eval-cache false)

run_timed() {
  label=$1
  shift
  tmp=$(mktemp "${TMPDIR:-/tmp}/host-build-cache-benchmark.XXXXXX")
  log=$(mktemp "${TMPDIR:-/tmp}/host-build-cache-benchmark-log.XXXXXX")
  set +e
  /usr/bin/env time -f '%e %M' -o "$tmp" "$@" >"$log" 2>&1
  status=$?
  set -e
  read -r elapsed max_rss _ <"$tmp" || { elapsed=unknown; max_rss=unknown; }
  rm -f "$tmp"
  printf '%s\telapsed_seconds=%s\tmax_rss_kib=%s\texit_status=%s\n' "$label" "$elapsed" "$max_rss" "$status"
  if [ "$status" -ne 0 ]; then
    tail -n 40 "$log" >&2
  fi
  rm -f "$log"
  return "$status"
}

printf 'revision=%s\nflake_ref=%s\nmode=dry-run\nruns=%s\n' "$rev" "$flake_ref" "$runs"
printf 'caveat=Dry-run compares planning/evaluation/substitution decisions only; it is not realization throughput. Run on thorny for operational conclusions.\n'

installables=()
for host in "${hosts[@]}"; do
  installables+=("$flake_ref#nixosConfigurations.$host.config.system.build.toplevel")
done
run_sequential() {
  run=$1
  # The single-quoted body intentionally expands positional parameters in the child shell.
  # shellcheck disable=SC2016
  run_timed "run=$run shape=sequential:x86-hosts" bash -c '
    for installable in "$@"; do
      nix build --accept-flake-config --dry-run --no-link --no-write-lock-file \
        --option eval-cache false "$installable"
    done
  ' bash "${installables[@]}"
}

run_multi() {
  run=$1
  run_timed "run=$run shape=multi:x86-hosts" nix build "${common_args[@]}" "${installables[@]}"
}

# Fetch the immutable flake once outside the measured trials.
nix flake metadata --no-write-lock-file "$flake_ref" >/dev/null

failed=0
run=1
while [ "$run" -le "$runs" ]; do
  if [ $((run % 2)) -eq 1 ]; then
    run_sequential "$run" || failed=1
    run_multi "$run" || failed=1
  else
    run_multi "$run" || failed=1
    run_sequential "$run" || failed=1
  fi
  run=$((run + 1))
done

exit "$failed"
