# Sentry error history

Sentry groups failures into issues and events with stack traces, tags, counts, first and last seen times, releases, and comments. It is useful for checks, catches, retries, fallbacks, and corrective changes.

## Search

Use the available Sentry skill, CLI, or integration. Read its instructions or help. Adapt to another error tracker when needed.

1. Discover the organization and project if needed.
2. Search exception classes, symbols, file paths, and error strings from the target.
3. For candidate issues, compare first seen, last seen, frequency, environments, and affected releases with the target's ship date.
4. Inspect representative events. Confirm that stack frames, tags, and breadcrumbs match the guarded condition.
5. Check releases near the commit and merge dates.

Redact credentials, tokens, cookies, personal data, and sensitive payloads as `[REDACTED]`. Preserve issue and event IDs, relevant frames, timestamps, and safe tags.

Treat AI root-cause analysis such as Seer only as a hypothesis. Events, stacks, timestamps, and author comments are stronger evidence.

## Strong evidence

Prefer an author comment that identifies the fix, a PR linked to an issue, or a stack through the target. First or last seen near a release and a sharp count change can support a connection but do not prove it.

## Failure modes

Fingerprint changes can regroup the same error under a new issue. Search immediately after an apparent stop. Releases contain many changes, so cross-check the exact commit. Upstream behavior can end an error without the target change. Manual "resolved" status does not prove a fix. Sampling can hide frequency.

## Return

For each issue, provide ID, title, link, project, first and last seen, count and known sampling, releases, a redacted representative stack excerpt, correlation with the ship date, and author comments or resolution notes.
