#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo 'Usage: review.sh [--zdr] [--deny-data-collection] openrouter/ORG/MODEL[#EFFORT] "PROMPT" [FILE ...]'
}

die() {
  printf 'Council review: %s\n' "$*" >&2
  exit 1
}

routing='{}'
while [[ $# -gt 0 ]]; do
  case "$1" in
    --zdr) routing=$(jq -c '.zdr = true' <<< "$routing") ;;
    --deny-data-collection) routing=$(jq -c '.data_collection = "deny"' <<< "$routing") ;;
    --help|-h) usage; exit 0 ;;
    --*) usage >&2; die "unknown option $1" ;;
    *) break ;;
  esac
  shift
done

if [[ $# -lt 2 ]]; then
  usage >&2
  exit 2
fi

model=$1
prompt=$2
shift 2
if [[ ! $model =~ ^openrouter/([a-z0-9._-]+/[a-z0-9._:-]+)(\#(low|medium|high|xhigh))?$ ]]; then
  die "expected an exact OpenRouter model ID with optional reasoning effort"
fi
model_id=${BASH_REMATCH[1]}
effort=${BASH_REMATCH[3]:-}

command -v opencode >/dev/null || die "OpenCode is missing from PATH"
command -v jq >/dev/null || die "jq is missing from PATH"
key=${OPENROUTER_API_KEY:-}
if [[ -z $key && -r /run/agenix/openrouter-api-key ]]; then
  key=$(cat /run/agenix/openrouter-api-key)
fi
[[ -n $key ]] || die "set OPENROUTER_API_KEY for this executor"

# A fixed title keeps OpenCode from sending the review prompt to a title model.
args=(run --standalone --model "$model" --agent plan --title 'Advisor council review' --format json)
for file do
  [[ $file = /* ]] || file="$PWD/$file"
  [[ -f $file && -r $file ]] || die "cannot read attachment $file"
  args+=(--file "$file")
done

# Supply explicit reasoning variants when the clean catalog is behind.
config=$(jq -cn --arg model "$model_id" --arg effort "$effort" --argjson routing "$routing" '
  {
    permission: {"*": "deny"},
    permissions: [{action: "*", resource: "*", effect: "deny"}]
  }
  | if $effort != "" or $routing != {} then
      .providers.openrouter.models[$model] = (
        {modelID: $model}
        | if $effort != "" then
            .capabilities.reasoning = {supported: true, effort: [$effort]}
            | .variants = [{id: $effort, body: {reasoning: {effort: $effort}}}]
          else . end
        | if $routing != {} then .body.provider = $routing else . end
      )
    else . end
')
work=$(mktemp -d "${TMPDIR:-/tmp}/council-review.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/home" "$work/scratch"
cd "$work/scratch"

# Consume the credential in Bash and pass the remaining stdin to OpenCode.
printf '%s\n%s' "$key" "$prompt" |
  env -i PATH="$PATH" HOME="$work/home" OPENCODE_CONFIG_CONTENT="$config" \
    OPENCODE_DISABLE_PROJECT_CONFIG=1 \
    bash -c 'IFS= read -r OPENROUTER_API_KEY; export OPENROUTER_API_KEY; exec opencode "$@"' \
    bash "${args[@]}" > "$work/events.jsonl" || status=$?

# OpenCode can emit a provider error as a JSON event and still exit zero.
# It can also recover from an error and produce a successful text response.
if ! jq -ser --argjson status "${status:-0}" '
  reduce .[] as $event ({text: [], error: null};
    if $event.type == "error" then .error = $event.error.message | .text = []
    elif $event.type == "text" then .text += [$event.part.text] | .error = null
    else . end)
  | if .error then error(.error)
    elif $status != 0 or (.text | length) == 0 then error("OpenCode returned no successful review")
    else .text[] end
' "$work/events.jsonl"; then
  die "OpenRouter request failed for $model"
fi
