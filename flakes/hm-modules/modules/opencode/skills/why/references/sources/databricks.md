# Databricks Analytics & System Tables

## What this source contains

Databricks can be the product-analytics, data-pipeline, and warehouse-telemetry layer. It may complement Datadog's *infra/runtime* view with a *product/data* view (what users did, which experiments ran, how feature usage evolved, where a threshold constant came from).

All warehouse names, table/model patterns, columns, deduplication or clustering properties, and refresh cadences below are **illustrative upstream conventions, not portable Databricks guarantees**. Replace angle-bracket placeholders with names discovered in the current workspace. Discover catalogs, schemas, tables, and columns before running analytical queries; do not query an example identifier merely because it appears here.

- **Product analytics events.** Illustratively, a raw `<catalog>.<event_schema>.<raw_event_table>` and typed per-event dbt models in `<analytics_catalog>.<analytics_schema>.<typed_event_model>`. User behavior: feature invocations, clicks, accepts/rejects, submissions, client-reported errors. Whether models are typed or deduplicated must be verified locally.
- **Usage & billing events.** Illustrative `<catalog>.<event_schema>.<usage_event_table>` and `<analytics_catalog>.<analytics_schema>.<usage_model>` tables. For cost- or volume-driven decisions.
- **Experiment / feature-flag data.** Exposure and outcome tables. **Schema is company-specific.** Probe with `SHOW TABLES` before assuming names.
- **System tables.** `system.query.history`, `system.compute.warehouses`, `system.billing.*`, `system.access.audit`. Answer "was this query expensive?", "how often did anyone run this?", "when did warehouse load spike?"
- **dbt lineage.** Where present, models in `<analytics_catalog>.<analytics_schema>` reveal what pipelines depend on a table/field; upstream changes frequently motivate consumer-code changes.
- **Databricks notebooks.** Exploratory analyses engineers wrote before code changes. They may not be queryable through the available SQL interface. If you suspect the rationale lives in an inaccessible notebook, name it as a gap.

## How to search it

Use the available Databricks skill, CLI, SQL client, or integration and inspect its instructions or help rather than assuming a command or MCP schema. The current official CLI may expose `queries`, `query-history`, `warehouses`, `psql`, or raw API operations rather than a top-level `databricks sql` command. Use read-only query operations; if an asynchronous interface returns a statement ID, poll that result rather than re-running.

**Discover before querying.** Catalogs, schemas, tables, and columns are workspace-specific. First enumerate accessible catalogs/schemas and candidate tables using the available interface; then inspect the chosen table's schema. For example, only after discovering suitable placeholder values:

```sql
SHOW TABLES IN <analytics_catalog>.<analytics_schema> LIKE '*<keyword>*';
DESCRIBE TABLE <analytics_catalog>.<analytics_schema>.<candidate_table>;
```

**Time-bound every query.** Relevant tables may be huge and unconstrained scans may time out. After schema discovery, filter on the table's discovered event-time column (illustratively `<event_timestamp_column>`) or the documented time field of a verified system table, with a window bracketing the ship date, typically ~30 days before and after, wider only for strong reason.

**Prefer a verified curated model when appropriate.** In the upstream environment that inspired this example, `<analytics_catalog>.<analytics_schema>.<typed_event_model>` was typed, deduplicated, and liquid-clustered, while `<catalog>.<event_schema>.<raw_event_table>` could contain duplicates and untyped JSON. Those properties are not guaranteed by Databricks or dbt: verify model documentation, schema, uniqueness, table properties, and freshness locally. The illustrative upstream naming pattern was `stg_<source>_<event_name_with_underscores>`; discover the actual model rather than relying on it. Use raw data only when justified by the discovered pipeline and apply deduplication only according to verified event identity semantics.

**Illustrative upstream column conventions** (never a substitute for `DESCRIBE TABLE` or equivalent discovery):

- `_timestamp`, `_id`, `_auth_id`, `_request_id`, `event_name`. These were common upstream, not standard Databricks columns
- `properties_<name>`. Typed, underscore-cased event properties (`properties_entrypoint`, `properties_size_bytes`, …)
- `context_team_id`, `context_client_version`, `context_country`, `context_client_os`. Pre-extracted client context

### Investigation patterns that tend to pay off

Pick the table + column combination that matches the target:

1. **Event usage trajectory.** Daily counts on the relevant `stg_*` model across a ±30d window around the PR merge. A step function from zero to steady volume within a day or two of the merge is strong circumstantial evidence the PR launched the feature. A decay to zero suggests a deprecation or deletion.
2. **Guard-rail / defensive-check origin.** Distribution (median / p99 / max) of the relevant `properties_<name>` column in the 14 days *before* the PR. A p99 that matches the target's threshold constant suggests the number was chosen from data.
3. **Experiment / feature-flag lookup.** `SHOW TABLES ... LIKE '*experiment*'` to find the exposure table, then pull exposure counts by variant for the relevant flag key near the PR date.
4. **Query-history evidence for migrations, backfills, or perf rewrites.** `system.query.history` filtered by `statement_text ILIKE '%<table_or_symbol>%'` with a tight `start_time` window surfaces the expensive queries that likely motivated the change (sort by `total_duration_ms` or aggregate `SUM(read_bytes)`, `COUNT(*)`).
5. **dbt lineage.** If the target reads from or writes into a discovered `<analytics_catalog>.<analytics_schema>.<model>` model, the model's own VCS history (when available) often carries the rationale. Record that cross-source lead for the parent's bounded follow-up pass rather than implying the concurrent source-control investigator can consume it.

## What good evidence looks like here

Beyond the pattern shapes above:

- An error-classifying event's count drops to near zero in the days after a defensive-code PR. Suggests the PR resolved that error class
- An exposure table row names the target's feature-flag key with a "shipped" / "concluded" decision around the PR ship date

## Common pitfalls

- **Instrumented ≠ caused.** An event's existence means someone cared enough to log it, not that the target code exists *because* of it. Pair with a PR/commit citation from the source-control investigator before claiming causation.
- **Silent instrumentation changes.** A step function in event volume may mean a new event started being logged, not that user behavior changed. Check for instrumentation PRs in the same window before reading the ramp as a feature-launch signal.
- **Schema drift.** Event properties evolve; a column on the typed dbt model today may not have existed when the target was written. Older data may carry the property only inside raw `properties_json`.
- **Refresh cadence assumptions.** The upstream dbt models were often rebuilt hourly or daily, but no cadence is guaranteed. Discover freshness and pipeline schedules before choosing curated versus raw data. Do not deduplicate by an illustrative `_id` unless its identity semantics are verified.
- **Company-specific tables.** Experiment, feature-flag, billing, and usage tables vary. Reporting a result from a table whose existence you never confirmed is a classic failure mode. Probe with `SHOW TABLES` / `DESCRIBE TABLE` first.
- **Retention cliff.** If the relevant window predates the table's retention or the dbt model's creation date, that's a *gap*, not a null result. Name it explicitly so the synthesizer doesn't read "no results" as "no activity."
- **Notebooks may not be queryable.** If the available SQL interface cannot see Databricks notebooks and you suspect the rationale lives in one, return a gap.

## What to return

For each relevant finding:
- Type (product event / experiment exposure / usage or billing event / system-table row / dbt model)
- Fully-qualified table name and the exact query you ran
- Time window queried
- Compact numeric summary (counts, percentiles, first/last-seen timestamps). **Don't dump raw rows.**
- Temporal correlation with the target's ship date (e.g., "first row 2024-08-15; PR #49074 merged 2024-08-14")
- Relevance + strength: direct / circumstantial / weak
