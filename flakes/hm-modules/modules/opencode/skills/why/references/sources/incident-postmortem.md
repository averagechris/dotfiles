# Incident and postmortem angle

This is not a seventh source. Add these searches within each available category when code looks defensive, such as checks, retries, timeouts, rate limits, flags, egress guards, or OOM handling.

- **Source control:** search incident IDs, reverts, defensive fixes, and follow-up commits.
- **Issue tracking:** search `incident`, `sev-*`, `postmortem-action-item`, and `reliability` labels or terms.
- **Long-form documents:** search postmortems for the target, service, feature, and error text.
- **Infrastructure observability:** search incident timelines, monitors, and dashboards near the change date.
- **Error tracking:** compare first and last seen, stack traces, and releases with the ship date.
- **Product analytics:** look for bounded changes in user-visible error or retry events around the incident and fix.

Fetch a full postmortem when found. Its action items may link directly to code. Corroboration across incident, ticket, postmortem, PR, and telemetry records strengthens the account, but timing alone does not prove causation.

Skip this angle when the target has no plausible defensive or incident-driven role.
