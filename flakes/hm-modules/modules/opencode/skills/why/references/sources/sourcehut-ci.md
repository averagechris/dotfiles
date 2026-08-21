# SourceHut CI

Use the `srht-ci` skill for builds.sr.ht when available and relevant to the repository. Do not search issues in this playbook. Leave those to the issue-tracker investigator.

Inspect the build ID, manifest and task names, status, timestamps, failing command, and the smallest useful log excerpt. CI failures can corroborate a technical constraint or regression. They rarely prove intent by themselves. Link the build and task or log instead of dumping a large log.

Keep searches bounded by repository, build ID, commit, and time range. Record retention and access limits. Redact tokens, environment values, private URLs, and sensitive payloads as `[REDACTED]`.
