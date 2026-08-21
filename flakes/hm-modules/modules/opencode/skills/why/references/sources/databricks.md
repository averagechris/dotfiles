# Databricks analytics and system tables

Databricks may contain product events, usage and billing data, experiment exposures, dbt models, query history, audit records, and notebooks. This product and data view complements infrastructure telemetry.

All names below are placeholders, not Databricks standards. Discover the current workspace before querying. Never run an example identifier as if it were real.

## Search

Use the available Databricks skill, CLI, SQL client, or integration. Read its instructions or help. The official CLI may expose `queries`, `query-history`, `warehouses`, `psql`, or raw API calls instead of `databricks sql`. Use read-only operations. Poll an asynchronous statement ID instead of submitting the query again.

Discover catalogs, schemas, tables, and columns first:

```sql
SHOW TABLES IN <analytics_catalog>.<analytics_schema> LIKE '*<keyword>*';
DESCRIBE TABLE <analytics_catalog>.<analytics_schema>.<candidate_table>;
```

Verify documentation, schema, identity semantics, table properties, freshness, and lineage. Prefer a curated model only after verifying that it is suitable. Raw events may contain duplicates or untyped JSON.

Bound every query by the discovered event-time field. Start near 30 days before and after the ship date. Widen only for a stated reason.

Useful patterns:

- Daily event counts can show launch, deprecation, or instrumentation changes.
- Pre-change median, p99, and maximum values can suggest the origin of a threshold.
- Exposure counts by flag and variant can place an experiment decision near a release.
- Bounded `system.query.history` searches can reveal costly migrations, backfills, or rewrites.
- dbt lineage can identify a model whose VCS history deserves bounded cross-source follow-up.

## Failure modes

Instrumentation does not prove causation. A volume jump may be a logging change. Schemas and properties drift over time. Verify that a column existed in the relevant window. Do not assume refresh cadence or deduplicate on a convenient ID without proven semantics. A retention cutoff, model creation date, inaccessible notebook, or missing permission is a gap, not a null result.

## Return

For each finding, provide the type, fully qualified table, exact query, time window, compact numeric summary, first and last seen when useful, ship-date correlation, and evidence strength. Do not dump raw rows.
