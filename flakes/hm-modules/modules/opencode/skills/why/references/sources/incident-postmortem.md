# Incident & Postmortem Context

Not a separate source, a **cross-cutting angle**. Incidents often motivate defensive code ("we added this check after the X outage"), so if the target looks defensive (null checks, retry logic, timeout handling, rate limiting, feature flags), specifically hunt for incident history across every available source:

- **Notion**: search for postmortems mentioning the target file, feature, or error string
- **Linear**: look for tickets labeled `incident`, `sev-*`, `postmortem-action-item`, `reliability`
- **Source control**: commits with messages like "fix for incident", "add defensive check", "revert" followed by "re-apply with..." are strong signals
- **Datadog**: search formal incident records and timelines, plus dashboards and monitors created as postmortem action items; map these searches to the discovered skill, CLI, or integration after inspecting its instructions or help
- **Sentry**: issues whose first-seen/last-seen window aligns with the target's PR ship date; stack traces through the target
- **Databricks**: product-analytics events that classify an error condition (client-reported failures, user-visible retry events, etc.) often spike during an incident window. A drop in that event count after the target PR ships is circumstantial support that the target code resolved the user-visible symptom, even when Datadog/Sentry signal is noisy.

If you find an incident link, fetch the full postmortem. Postmortems typically have an "Action Items" section that ties directly to code changes. When multiple sources corroborate (a Datadog incident ID appears in a Linear ticket, which appears in a Notion postmortem that links to the target PR, and the Databricks error-event count drops after the fix), the evidence is especially strong.

Worth spending time on when the code's defensive character makes an incident-driven origin plausible. Skip it for code that doesn't look defensive.
