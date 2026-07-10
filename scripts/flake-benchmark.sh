#!/usr/bin/env bash
set -euo pipefail

schema="dotfiles.flake-benchmark.v1"
hosts="suremac trap thorny tom cruber tater trainwreck taz tootsie"
darwin_hosts="suremac"

usage() {
  cat <<'USAGE'
Usage: flake-benchmark [OPTIONS]

Benchmark Nix flake evaluation without building or substituting outputs.

Options:
  --target TARGET     root-check, host:<name>, or all-hosts (repeatable)
  --list-targets      Print available targets and exit
  --runs N            Measured runs per target (default: 3)
  --warmup N          Warmup runs per target, recorded as phase=warmup (default: 1)
  --output PATH       JSON Lines output path (default: stdout)
  --prepare           Run online preparation before measured samples
  --offline           Run measured samples with Nix --offline (default)
  --no-offline        Allow network access during measured samples
  --allow-dirty       Permit and record a dirty checkout
  --repo PATH         Flake checkout to benchmark (default: cwd)
  -h, --help          Show this help

Default targets are root-check plus every configured host.
USAGE
}

die() { printf 'error: %s\n' "$*" >&2; exit 2; }

is_uint() { case "$1" in ''|*[!0-9]*) return 1;; *) return 0;; esac; }

is_host() { case " $hosts " in *" $1 "*) return 0;; *) return 1;; esac; }
is_darwin_host() { case " $darwin_hosts " in *" $1 "*) return 0;; *) return 1;; esac; }

list_targets() {
  printf 'root-check\nall-hosts\n'
  for host in $hosts; do printf 'host:%s\n' "$host"; done
}

json_emit() {
  if [ -n "$output" ]; then
    printf '%s\n' "$1" >>"$output"
  else
    printf '%s\n' "$1"
  fi
}

nix_config_value_json() {
  key=$1
  if config=$(nix config show --json 2>/dev/null); then
    printf '%s' "$config" | jq -c --arg key "$key" '
      if has($key) then
        if .[$key] | type == "object" and has("value") then .[$key].value else .[$key] end
      else null end
    '
  elif config=$(nix show-config --json 2>/dev/null); then
    printf '%s' "$config" | jq -c --arg key "$key" '
      if has($key) then
        if .[$key] | type == "object" and has("value") then .[$key].value else .[$key] end
      else null end
    '
  elif config=$(nix show-config 2>/dev/null); then
    printf '%s\n' "$config" | jq -R -s -c --arg key "$key" '
      split("\n")
      | map(select(startswith($key + " = ")) | sub("^[^=]+ = "; ""))
      | first // null
    '
  else
    printf 'null\n'
  fi
}

set_target_command() {
  target=$1
  if [ "$target" = root-check ]; then
    cmd=(nix flake check "$repo" --no-build --no-write-lock-file --option eval-cache false)
    return
  fi
  host=${target#host:}
  if is_darwin_host "$host"; then
    attr="darwinConfigurations.${host}.system"
  else
    attr="nixosConfigurations.${host}.config.system.build.toplevel.drvPath"
  fi
  cmd=(nix eval "${repo}#${attr}" --raw --no-write-lock-file --option eval-cache false)
}

run_nix_sample() {
  target=$1 phase=$2 run=$3 offline_value=$4
  tmp=$(mktemp "${TMPDIR:-/tmp}/flake-benchmark-time.XXXXXX")
  err=$(mktemp "${TMPDIR:-/tmp}/flake-benchmark-stderr.XXXXXX")
  set_target_command "$target"
  if [ "$offline_value" = true ]; then
    cmd+=(--offline)
  fi

  set +e
  /usr/bin/env time -f '%e %M' -o "$tmp" "${cmd[@]}" >/dev/null 2>"$err"
  status=$?
  set -e

  if read -r elapsed max_rss _ <"$tmp"; then :; else elapsed=null; max_rss=null; fi
  rm -f "$tmp"
  if [ "$status" -ne 0 ]; then
    printf 'flake-benchmark: %s sample failed for %s with exit status %s\n' "$phase" "$target" "$status" >&2
    if [ -s "$err" ]; then
      while IFS= read -r line; do
        printf 'flake-benchmark stderr: %s\n' "$line" >&2
      done <"$err"
    fi
  fi
  rm -f "$err"
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  json_emit "$(jq -cn \
    --arg schema "$schema" --arg timestamp "$ts" --arg revision "$revision" \
    --arg system "$current_system" --arg nix_version "$nix_version" \
    --arg target "$target" --arg phase "$phase" --argjson run "$run" \
    --argjson warmup "$([ "$phase" = warmup ] && printf true || printf false)" \
    --argjson offline "$offline_value" --arg elapsed "$elapsed" --arg max_rss "$max_rss" \
    --argjson dirty "$dirty" --argjson status "$status" \
    '{schema:$schema,timestamp:$timestamp,revision:$revision,dirty:$dirty,current_system:$system,nix_version:$nix_version,target:$target,phase:$phase,run:$run,warmup:$warmup,offline:$offline,eval_cache:false,elapsed_seconds:($elapsed|tonumber?),max_rss_kib:($max_rss|tonumber?),exit_status:$status}')"
  [ "$status" -eq 0 ]
}

runs=3
warmup=1
output=""
prepare=false
offline=true
allow_dirty=false
repo=$(pwd)
targets=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) [ "$#" -ge 2 ] || die "--target requires a value"; targets="$targets $2"; shift 2;;
    --runs) [ "$#" -ge 2 ] || die "--runs requires a value"; is_uint "$2" || die "--runs must be a positive integer"; [ "$2" -gt 0 ] || die "--runs must be a positive integer"; runs=$2; shift 2;;
    --warmup) [ "$#" -ge 2 ] || die "--warmup requires a value"; is_uint "$2" || die "--warmup must be a non-negative integer"; warmup=$2; shift 2;;
    --output) [ "$#" -ge 2 ] || die "--output requires a path"; output=$2; shift 2;;
    --prepare) prepare=true; shift;;
    --offline) offline=true; shift;;
    --no-offline) offline=false; shift;;
    --allow-dirty) allow_dirty=true; shift;;
    --repo) [ "$#" -ge 2 ] || die "--repo requires a path"; repo=$2; shift 2;;
    --list-targets) list_targets; exit 0;;
    -h|--help) usage; exit 0;;
    *) die "unknown option: $1";;
  esac
done

[ -d "$repo" ] || die "repo path does not exist: $repo"
repo=$(cd "$repo" && pwd -P)
[ -f "$repo/flake.nix" ] || die "repo path is missing flake.nix: $repo"

if [ -n "$output" ]; then
  case "$output" in
    /*) output_abs=$output ;;
    *) output_abs=$(pwd -P)/$output ;;
  esac
  case "$output_abs" in
    "$repo"|"$repo"/*) die "--output must be outside the benchmarked repository" ;;
  esac
fi

if [ -z "$targets" ]; then
  targets="root-check"
  for host in $hosts; do targets="$targets host:$host"; done
fi

expanded=""
for target in $targets; do
  case "$target" in
    root-check) expanded="$expanded root-check";;
    all-hosts) for host in $hosts; do expanded="$expanded host:$host"; done;;
    host:*) host=${target#host:}; is_host "$host" || die "unknown host: $host"; expanded="$expanded $target";;
    *) die "unknown target: $target";;
  esac
done

dirty=false
if command -v jj >/dev/null 2>&1 && jj --repository "$repo" root >/dev/null 2>&1; then
  revision=$(jj --repository "$repo" log -r @ --no-graph -T 'commit_id.short()' --no-pager --color=never)
  if [ -n "$(jj --repository "$repo" diff --summary --no-pager --color=never)" ]; then dirty=true; fi
elif command -v git >/dev/null 2>&1 && git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  revision=$(git -C "$repo" rev-parse --short HEAD)
  if [ -n "$(git -C "$repo" status --porcelain)" ]; then dirty=true; fi
else
  revision=unknown
  dirty=true
fi

if [ "$dirty" = true ] && [ "$allow_dirty" != true ]; then
  die "checkout is dirty; use --allow-dirty to benchmark and record dirty=true"
fi

if [ -n "$output" ]; then
  mkdir -p "$(dirname "$output")"
  : >"$output"
fi

current_system=$(nix eval --raw --impure --expr builtins.currentSystem)
nix_version_raw=$(nix --version)
nix_version=${nix_version_raw##* }
substituters_json=$(nix_config_value_json substituters)
builders_json=$(nix_config_value_json builders)
trusted_public_keys_json=$(nix_config_value_json trusted-public-keys)
builders_use_substitutes_json=$(nix_config_value_json builders-use-substitutes)
if [ -f "$repo/flake.lock" ]; then
  flake_lock_sha256=$(nix hash file --type sha256 --base16 "$repo/flake.lock")
else
  flake_lock_sha256=""
fi
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
target_json=$(printf '%s' "$expanded" | tr ' ' '\n' | jq -R 'select(length > 0)' | jq -s .)
json_emit "$(jq -cn --arg schema "$schema" --arg timestamp "$ts" --arg revision "$revision" --argjson dirty "$dirty" --arg system "$current_system" --arg nix_version "$nix_version" --arg nix_version_raw "$nix_version_raw" --argjson targets "$target_json" --argjson substituters "$substituters_json" --argjson trusted_public_keys "$trusted_public_keys_json" --argjson builders "$builders_json" --argjson builders_use_substitutes "$builders_use_substitutes_json" --arg flake_lock_sha256 "$flake_lock_sha256" --argjson runs "$runs" --argjson warmup_count "$warmup" --argjson offline_default "$offline" --argjson prepare_requested "$prepare" '{schema:$schema,timestamp:$timestamp,record:"metadata",revision:$revision,dirty:$dirty,current_system:$system,nix_version:$nix_version,nix_version_raw:$nix_version_raw,substituters:$substituters,trusted_public_keys:$trusted_public_keys,builders:$builders,builders_use_substitutes:$builders_use_substitutes,flake_lock_sha256:(if $flake_lock_sha256 == "" then null else $flake_lock_sha256 end),benchmark_config:{runs:$runs,warmup:$warmup_count,offline:$offline_default,prepare:$prepare_requested},targets:$targets,eval_cache:false,warmups_recorded:true}')"

if [ "$prepare" = true ]; then
  prepare_failed=0
  for target in $expanded; do
    if ! run_nix_sample "$target" prepare 0 false >/dev/null; then prepare_failed=1; fi
  done
  if [ "$prepare_failed" -ne 0 ]; then
    printf 'flake-benchmark: prepare failed; stopping before measured samples\n' >&2
    exit 1
  fi
fi

failed=0
for target in $expanded; do
  i=1
  while [ "$i" -le "$warmup" ]; do
    run_nix_sample "$target" warmup "$i" "$offline" >/dev/null || true
    i=$((i + 1))
  done
  i=1
  while [ "$i" -le "$runs" ]; do
    if ! run_nix_sample "$target" measured "$i" "$offline"; then failed=1; fi
    i=$((i + 1))
  done
done

exit "$failed"
