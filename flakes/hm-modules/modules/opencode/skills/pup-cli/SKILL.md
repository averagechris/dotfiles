---
name: pup-cli
description: Use when querying Datadog with the local pup CLI, especially logs, metrics, monitors, Bits AI, docs, or raw Datadog API calls.
---

# Pup CLI

Use `pup` for Datadog. Keep output small.

## Token-saving defaults

```bash
# OpenCode may trigger pup's agent envelope; disable it for compact raw output.
pup ... --read-only --no-agent --jq 'PAYLOAD_JQ' -o csv

# Discover shape without dumping values.
pup COMMAND --limit 1 --read-only --no-agent --jq 'paths(scalars)|join(".")' -o csv
```

- Prefer `--read-only` unless the user explicitly asks to create/update/delete.
- Prefer `--no-agent` to avoid the `status/data/metadata` wrapper. Use `--agent`
  only when that envelope is useful.
- `--jq` runs on the response payload before formatting, not on the agent wrapper.
- Prefer `-o csv` for flat selected fields; use `-o json` only for nested data.
- Always bound data with `--from`, `--to`, `--limit`, `--page`, or `--per-page`.
- Aggregate first; fetch raw logs/traces only after narrowing the query.
- Flatten with `--jq` before `-o csv`; nested payloads otherwise become JSON-in-CSV.
- Avoid broad `paths(scalars)` on spans/logs except with `--limit 1`; jq errors can
  dump too much context.

## Sure stack context

On `suremac`, use `sure-stack-context` for Sure-specific service, ecosystem, and
environment hints.

## Compact patterns

```bash
# APM: top services by traced time.
pup apm services stats --read-only --no-agent --env production --from 30m \
  --jq '.data.attributes.services_stats|sort_by(.totalDuration|tonumber)|reverse|.[0:15]|map({service,operation,hits:(.hits|tonumber),avg_ms:(.latencyAvg/1000000),p95_ms:(.latencyP95/1000000),p99_ms:(.latencyP99/1000000),total_s:((.totalDuration|tonumber)/1000000000)})' -o csv

# Traces: top services with spans over 1s.
pup traces aggregate --read-only --no-agent \
  --query 'env:production @duration:>1000000000' --from 30m \
  --compute count --group-by service \
  --jq '.data|map({service:.attributes.by.service,count_gt_1s:.attributes.compute.c0})|sort_by(.count_gt_1s)|reverse|.[0:15]' -o csv

# Logs: flatten aggregate buckets before CSV.
pup logs aggregate --read-only --no-agent \
  --query 'env:production status:error' --from 30m --group-by service \
  --limit 20 --sort count \
  --jq '.data.buckets|map({service:.by.service,count:.computes.c0})' -o csv

# Metrics: summarize timeseries points.
pup metrics query --read-only --no-agent \
  --query 'avg:trace.django.request.duration{env:production,service:SERVICE}' --from 30m \
  --jq '.series|map({scope,metric,points:(.pointlist|length),avg_s:([.pointlist[][1]]|add/length),max_s:([.pointlist[][1]]|max),last_s:(.pointlist[-1][1]//null)})' -o csv

# Discover metric names.
pup metrics list --read-only --no-agent --filter 'trace.*duration*' -o csv

# Monitors / raw API escape hatch.
pup monitors search --read-only --no-agent --query 'service:api' --per-page 10 -o csv
pup api v2/monitors --read-only --no-agent -F page=0 --jq '.' -o json

# Docs AI is unauthenticated; Bits AI uses Datadog auth.
pup docs ask 'short Datadog question'
pup bits ask --no-stream 'short account-specific question'
```

`pup profiling` does not expose flamegraphs yet. If profiling/flamegraphs matter,
ask Chris to enable the Datadog MCP temporarily; it is disabled by default to save
tokens.

Run `pup <group> <command> --help` before guessing flags.
