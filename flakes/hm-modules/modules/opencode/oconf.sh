#!/usr/bin/env bash
# oconf - temporary opencode model overrides for the current shell session.
# Prints shell exports on stdout (eval them via the `oconf` shell function);
# human-readable summaries go to stderr. See docs/opencode.md.

usage() {
  cat <<'EOF'
usage: oconf [-v variant] <provider/model> [agent ...]
       oconf
       oconf -u

Print shell exports that override opencode models for the current shell
session. Nothing is written to any config file. Use the `oconf` shell
function (installed for zsh and bash) to apply them:

  oconf                                          interactive flow
  oconf && opencode --standalone                 launch with overrides
  oconf openrouter/x-ai/grok-4.5 && opencode --standalone
                                                trial for every role
  oconf -v high <model> minion build && opencode --standalone
                                                variant + specific agents
  oconf -u                                       clear overrides

Interactive flow: pick a trial model (live from `opencode models`), choose
the scope (all roles / session only / specific agents), then review and
tweak the whole plan in your editor before applying. Quit the editor with
an empty plan to cancel.

Set OCONF_PLAN_FILE to skip the pickers and editor and read a plan file
directly (one `<agent> = <model> [variant=<v>]` line per override).
EOF
}

die() {
  echo "oconf: $*" >&2
  exit 2
}

config_dir="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
overrides='{"agent":{}}'
top_model=""
variant=""

# Print "name<TAB>current-model-or-empty" for every configured agent,
# discovered live from the deployed agent files and generated config.
discover_agents() {
  local f base m
  for f in "$config_dir"/agents/*.md; do
    [[ -f "$f" ]] || continue
    base=$(basename "$f" .md)
    m=$(sed -n 's/^model:[[:space:]]*//p' "$f" | head -n 1)
    printf '%s\t%s\n' "$base" "$m"
  done
  if [[ -f "$config_dir/opencode.json" ]]; then
    jq -r '.agent | to_entries[] | select(.value.model != null) | "\(.key)\t\(.value.model)"' \
      "$config_dir/opencode.json" 2>/dev/null
  fi
}

add_override() {
  overrides=$(jq -c --arg a "$1" --arg m "$2" --arg v "${3:-}" '
    .agent[$a] = ({model: $m} + (if $v == "" then {} else {variant: $v} end))
  ' <<<"$overrides")
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

emit() {
  if [[ "$overrides" == '{"agent":{}}' && -z "$top_model" ]]; then
    die "nothing overridden"
  fi
  local config_json
  config_json=$(jq -c --arg m "$top_model" \
    'if $m == "" then . else . + {model: $m} end' <<<"$overrides")
  {
    echo "--- oconf overrides ---"
    jq -r '"session: " + (.model // "unchanged"),
           (.agent | to_entries[] | .key + ": " + .value.model +
             (if .value.variant then " (variant " + .value.variant + ")" else "" end))' \
      <<<"$config_json"
    echo "clear with: oconf -u"
    echo "launch with: opencode --standalone (an existing V2 server keeps its own config)"
  } >&2
  # JSON never contains single quotes, so plain quoting is safe.
  case "$config_json" in *"'"*) die "unexpected quote in generated config" ;; esac
  printf "export OPENCODE_CONFIG_CONTENT='%s'\n" "$config_json"
}

# V2's model list can be empty while a cold location activates its plugins.
# Retry only empty successful responses, never hide a CLI/transport failure.
live_models() {
  local models attempt
  for attempt in 1 2 3 4 5; do
    models=$(opencode models 2>/dev/null) || return $?
    if [[ -n "$models" ]]; then
      printf '%s\n' "$models"
      return 0
    fi
    [[ "$attempt" == 5 ]] || sleep 0.25
  done
}

# Validate every model mentioned in a plan against the live model list.
validate_plan() {
  local file="$1" model_list bad line key rest model
  model_list=$(live_models) || die "'opencode models' failed"
  [[ -n "$model_list" ]] || die "opencode reports no available models"
  bad=""
  while IFS= read -r line; do
    line="${line%%#*}"
    [[ -n "${line//[[:space:]]/}" ]] || continue
    key=$(trim "${line%%=*}")
    rest=$(trim "${line#*=}")
    model=""
    local toks tok
    read -r -a toks <<<"$rest"
    for tok in "${toks[@]}"; do
      case "$tok" in variant=*) ;; *) model="${model:+$model }$tok" ;; esac
    done
    if ! grep -qxF "$model" <<<"$model_list"; then
      bad+="  $key = $model"$'\n'
    fi
  done <"$file"
  [[ -z "$bad" ]] || die "unknown model(s) in plan (not offered by 'opencode models'):
${bad}Fix the plan and retry."
}

# Parse a plan file into top_model/overrides. Returns nonzero for an empty plan.
apply_plan() {
  local file="$1" line key rest model toks tok
  overrides='{"agent":{}}'
  top_model=""
  while IFS= read -r line; do
    line="${line%%#*}"
    [[ -n "${line//[[:space:]]/}" ]] || continue
    key=$(trim "${line%%=*}")
    rest=$(trim "${line#*=}")
    [[ -n "$key" && -n "$rest" ]] || die "malformed plan line: $line"
    model=""
    variant=""
    read -r -a toks <<<"$rest"
    for tok in "${toks[@]}"; do
      case "$tok" in
        variant=*) variant="${tok#variant=}" ;;
        *) model="${model:+$model }$tok" ;;
      esac
    done
    if [[ "$key" == "*" ]]; then
      top_model="$model"
    else
      add_override "$key" "$model" "$variant"
    fi
  done <"$file"
  if [[ "$overrides" == '{"agent":{}}' && -z "$top_model" ]]; then
    return 1
  fi
}

# Run $VISUAL/$EDITOR on a file. When invoked through the `oconf` shell
# function, our stdout is captured but stdin is still the user's terminal;
# give the editor the terminal so full-screen editors work.
run_editor() {
  local file="$1" ed="${VISUAL:-${EDITOR:-vi}}"
  if [[ -t 0 && ! -t 1 ]]; then
    "$ed" "$file" </dev/tty >/dev/tty 2>&1
  else
    "$ed" "$file"
  fi
}

# Emit comment lines listing notable models (newest first, free tier) drawn
# from OpenRouter's public catalog, restricted to models this opencode can
# actually access. Cached for a day; silently empty when offline.
discovery_notes() {
  local model_list="$1"
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/oconf"
  local cache_file="$cache_dir/openrouter-models.json"
  local ttl=$((24 * 3600)) mtime now
  mkdir -p "$cache_dir" 2>/dev/null || return 0
  mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)
  now=$(date +%s)
  if ((now - mtime > ttl)); then
    curl -fsSL --max-time 5 https://openrouter.ai/api/v1/models \
      -o "$cache_file.tmp" 2>/dev/null &&
      mv "$cache_file.tmp" "$cache_file" || true
  fi
  [[ -s "$cache_file" ]] || return 0

  # Map OpenRouter ids onto this opencode's offered models (openrouter/*
  # prefixed), annotated with context size and release date, newest first.
  local -a usable=()
  local id line
  while IFS=$'\t' read -r id ctx ts; do
    [[ -n "$id" ]] || continue
    line="openrouter/$id"
    grep -qxF "$line" <<<"$model_list" || continue
    usable+=("$(printf '%s\t%s\t%s' "$line" "$ctx" "$ts")")
  done < <(jq -r '.data | sort_by(-.created)[]
            | [.id, .context_length, .created]
            | @tsv' "$cache_file" 2>/dev/null)
  ((${#usable[@]} > 0)) || return 0

  # Free-tier set, extracted once.
  local -A free_set=()
  while IFS= read -r id; do
    [[ -n "$id" ]] && free_set[$id]=1
  done < <(jq -r '.data[] | select(.pricing.prompt == "0") | .id' "$cache_file" 2>/dev/null)

  local cutoff=$((now - 60 * 24 * 3600))
  local -a recent=() free=()
  local entry m ctx ts d oid
  for entry in "${usable[@]}"; do
    IFS=$'\t' read -r m ctx ts <<<"$entry"
    oid="${m#openrouter/}"
    if ((ts >= cutoff)); then
      d=$(date -u -r "$ts" +%F 2>/dev/null || date -u -d "@$ts" +%F 2>/dev/null || echo "?")
      recent+=("$(printf '%-45s %s, released %s' "$m" "$(human_size "$ctx")" "$d")")
    fi
    [[ -n "${free_set[$oid]:-}" ]] && free+=("$m")
  done

  echo "#"
  echo "# Notable models right now:"
  if ((${#recent[@]} > 0)); then
    echo "#   new on OpenRouter:"
    printf '#     %s\n' "${recent[@]:0:10}"
  fi
  if ((${#free[@]} > 0)); then
    echo "#   free to try:"
    printf '#     %s\n' "${free[@]:0:8}"
  fi
}

human_size() {
  local n="$1"
  if ((n >= 1024 * 1024)); then
    echo "$((n / 1024 / 1024))M ctx"
  elif ((n >= 1024)); then
    echo "$((n / 1024))K ctx"
  else
    echo "${n} ctx"
  fi
}

interactive_flow() {
  command -v fzf >/dev/null 2>&1 || die "fzf is required for interactive mode"
  local model_list trial_model scope choice
  model_list=$(live_models) || die "'opencode models' failed"
  [[ -n "$model_list" ]] || die "opencode reports no available models"

  trial_model=$(printf '%s\n' "$model_list" | fzf --height=50% --reverse \
    --prompt="trial model (esc=session unchanged): ") || trial_model=""

  scope="none"
  if [[ -n "$trial_model" ]]; then
    scope=$(printf '%s\n' \
      "all roles      - session model + every pinned agent" \
      "session only   - leave every agent alone" \
      "pick agents    - choose which agents get it" |
      fzf --height=20% --reverse --prompt="apply to: " --header="trial model: $trial_model") ||
      die "cancelled"
  fi

  local -a picked=()
  if [[ "$scope" == pick* ]]; then
    while IFS= read -r choice; do
      [[ -n "$choice" ]] || continue
      picked+=("$(trim "${choice%%\[*}")")
    done < <(discover_agents | sort -u | awk -F'\t' \
      '{ printf "%s [%s]\n", $1, ($2 == "" ? "inherits session" : $2) }' |
      fzf --multi --height=50% --reverse \
        --prompt="agents (tab=toggle, enter=apply): ") || die "cancelled"
    [[ ${#picked[@]} -gt 0 ]] || die "no agents selected"
  fi

  # Draft the plan, then hand it to the editor for review and tweaks.
  # plan_file is deliberately global: the EXIT trap fires after this
  # function's locals are gone.
  plan_file=$(mktemp "${TMPDIR:-/tmp}/oconf-plan.XXXXXX")
  trap 'rm -f "$plan_file"' EXIT
  {
    echo "# oconf trial plan - edit, then save and quit to apply."
    echo "#"
    echo "#   <agent> = <model> [variant=<v>]    override one agent"
    echo "#   *       = <model>                  override the session model"
    echo "# Comment out or delete lines to drop overrides; an empty plan cancels."
    echo "#"
    echo "# Agents:"
    while IFS=$'\t' read -r a m; do
      printf '#   %-14s %s\n' "$a" "${m:-(inherits session)}"
    done < <(discover_agents | sort -u)
    discovery_notes "$model_list"
    echo
    [[ -n "$trial_model" ]] && echo "* = $trial_model"
    case "$scope" in
      all*)
        while IFS=$'\t' read -r a m; do
          [[ -n "$m" ]] || continue
          v=""
          [[ -f "$config_dir/agents/$a.md" ]] &&
            v=$(sed -n "s/^variant:[[:space:]]*/ variant=/p" "$config_dir/agents/$a.md")
          printf '%s = %s%s\n' "$a" "$trial_model" "$v"
        done < <(discover_agents | sort -u)
        ;;
      pick*)
        local a m v
        for a in "${picked[@]}"; do
          m=$(awk -F'\t' -v k="$a" '$1 == k { print $2 }' < <(discover_agents))
          [[ -n "$m" ]] || continue
          v=""
          [[ -f "$config_dir/agents/$a.md" ]] &&
            v=$(sed -n "s/^variant:[[:space:]]*/ variant=/p" "$config_dir/agents/$a.md")
          printf '%s = %s%s\n' "$a" "$trial_model" "$v"
        done
        ;;
    esac
  } >"$plan_file"

  run_editor "$plan_file"
  validate_plan "$plan_file"
  if ! apply_plan "$plan_file"; then
    die "empty plan; cancelled"
  fi
  emit
}

# Options up front; stop at the first non-option word.
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    -u | --unset)
      printf 'unset OPENCODE_CONFIG_CONTENT\n'
      exit 0
      ;;
    -v)
      [[ $# -ge 2 ]] || die "-v requires a variant argument"
      variant="$2"
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

if [[ -n "${OCONF_PLAN_FILE:-}" ]]; then
  [[ -r "$OCONF_PLAN_FILE" ]] || die "cannot read OCONF_PLAN_FILE: $OCONF_PLAN_FILE"
  validate_plan "$OCONF_PLAN_FILE"
  apply_plan "$OCONF_PLAN_FILE" || die "empty plan"
  emit
  exit 0
fi

if [[ $# -eq 0 ]]; then
  interactive_flow
  exit 0
fi

if [[ -n "${OCONF_PLAN_FILE:-}" ]]; then
  [[ -r "$OCONF_PLAN_FILE" ]] || die "cannot read OCONF_PLAN_FILE: $OCONF_PLAN_FILE"
  validate_plan "$OCONF_PLAN_FILE"
  apply_plan "$OCONF_PLAN_FILE" || die "empty plan"
  emit
  exit 0
fi

model="$1"
shift

grep -q / <<<"$model" || die "model must look like provider/model-id (got: $model)"

agents=()
while [[ $# -gt 0 ]]; do
  agents+=("$1")
  shift
done

if [[ ${#agents[@]} -eq 0 ]]; then
  # Every role: the session model plus every agent that has a pinned model
  # in the deployed config (discovered live, not hardcoded).
  top_model="$model"
  while IFS=$'\t' read -r agent _current; do
    [[ -n "$agent" ]] || continue
    add_override "$agent" "$model" "$variant"
  done < <(discover_agents | sort -u)
else
  for agent in "${agents[@]}"; do
    add_override "$agent" "$model" "$variant"
  done
fi

emit
