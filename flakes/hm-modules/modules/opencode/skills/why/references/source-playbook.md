# Source playbooks

Use a playbook only when the question or a concrete lead makes its source relevant. One focused investigator may use several interfaces when that avoids duplicate work. Use agent history after normal searches or when a link is missing. It supplies leads, not evidence.

| Category | Playbook | Example source it documents |
|---|---|---|
| Source control history | [`code-archaeology.md`](./sources/code-archaeology.md), [`sourcehut-ci.md`](./sources/sourcehut-ci.md) | `jj` or git, `gh`, relevant builds.sr.ht CI |
| Issue / ticket tracker | [`linear.md`](./sources/linear.md), [`sourcehut-issues.md`](./sources/sourcehut-issues.md) | A tracker linked by repository conventions, commits, or the user |
| Long-form documents | [`repository-markdown.md`](./sources/repository-markdown.md), [`granola.md`](./sources/granola.md), [`notion.md`](./sources/notion.md) | Repository docs first; meeting notes or document systems when a lead points there |
| Infrastructure observability | [`datadog.md`](./sources/datadog.md) | Datadog (adapt for New Relic, Honeycomb, Grafana, Splunk) |
| Error / exception tracking | [`sentry.md`](./sources/sentry.md) | Sentry (adapt for Rollbar, Bugsnag, Airbrake) |
| Product analytics warehouse | [`databricks.md`](./sources/databricks.md) | Databricks SQL (adapt for Snowflake, BigQuery, ClickHouse, dbt) |

Also add [`incident-postmortem.md`](./sources/incident-postmortem.md) when the target looks defensive, such as a check, retry, timeout, rate limit, flag, egress guard, or OOM handler.

Use [`agent-history.md`](./sources/agent-history.md) across categories only to recover search trails and links. Verify each lead against an authoritative source.
