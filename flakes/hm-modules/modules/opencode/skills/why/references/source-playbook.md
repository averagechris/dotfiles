# Source playbooks

Use one playbook per available evidence category. Adapt it to another interface in the same category. Search repository Markdown directly for current documents. Use Notion for historical RFCs and PRDs.

| Category | Playbook | Example source it documents |
|---|---|---|
| Source control history | [`code-archaeology.md`](./sources/code-archaeology.md) | git, `gh` |
| Issue / ticket tracker | [`linear.md`](./sources/linear.md) | Linear (adapt for Jira, GitHub Issues, Plane, Shortcut) |
| Long-form documents | [`notion.md`](./sources/notion.md) | Repository Markdown first; historical Notion for older RFCs and PRDs |
| Infrastructure observability | [`datadog.md`](./sources/datadog.md) | Datadog (adapt for New Relic, Honeycomb, Grafana, Splunk) |
| Error / exception tracking | [`sentry.md`](./sources/sentry.md) | Sentry (adapt for Rollbar, Bugsnag, Airbrake) |
| Product analytics warehouse | [`databricks.md`](./sources/databricks.md) | Databricks SQL (adapt for Snowflake, BigQuery, ClickHouse, dbt) |

Also add [`incident-postmortem.md`](./sources/incident-postmortem.md) when the target looks defensive, such as a check, retry, timeout, rate limit, flag, egress guard, or OOM handler.
