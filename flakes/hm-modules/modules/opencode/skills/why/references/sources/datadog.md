# Datadog telemetry

Datadog records production behavior through metrics, monitors, dashboards, traces, logs, incidents, and notebooks. It can show runtime conditions around a change. It rarely proves why one line exists without another source.

## Search

Use the available Datadog skill, `pup`, or integration. Read its instructions or help. Adapt to another observability system when needed.

1. Identify the service and dependencies.
2. Search dashboards and monitors by service, feature, symbol, and error text. Record queries and thresholds.
3. Inspect metric metadata and bounded time series around the merge or release date.
4. Search logs by service, tags, symbols, and error text. Use a narrow time range, usually 30 days before and after the change. Aggregate counts instead of dumping events.
5. Inspect relevant spans and traces for timeouts, retries, slow paths, and cross-service behavior.
6. Search incidents near the change, especially for defensive code.

Redact credentials, tokens, cookies, personal data, and sensitive payloads as `[REDACTED]`. Keep identifiers, timestamps, and useful non-sensitive fields.

## Strong evidence

- a monitor threshold matching a code constraint
- an incident timeline naming the target or fix
- logs showing the guarded error before the change
- a metric spike before the change and stabilization after it
- a trace through the target under the relevant condition

Only explicit incident or author text may be Direct. Timing and matching values usually provide Supported or Inferred evidence.

## Failure modes

Correlation does not prove causation. Check neighboring changes. Dashboards reflect their authors' framing. Missing old telemetry may mean rename, deletion, retention, or access loss. Call that a gap, not a null result. Narrow noisy logs by service, tag, and time. Instrumentation shows attention, not necessarily motivation.

## Return

For each item, provide type, name, ID or link, owner and dates, exact query or condition, time window, compact result, relevance, and connection strength.
