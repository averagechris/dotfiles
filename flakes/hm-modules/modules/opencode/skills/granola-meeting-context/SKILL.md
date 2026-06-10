---
name: granola-meeting-context
description: Use when the user asks about meeting notes, transcripts, what was discussed, or whether PR/code/work matches a prior conversation.
---

# Granola Meeting Context

Use the local `granola` CLI to pull in meeting-note context when it could help
with requirements, decisions, follow-ups, or project history. This is especially
relevant for requests like “I spoke with Will about this PR; is it inline with
what we discussed?” Keep output small: find candidates first, then bundle only
relevant notes.

## Quick workflow

```bash
# Optional sanity check if credentials/cache seem stale
granola auth status --validate --output json-compact

# Find likely notes
granola search TERMS --output json-compact
granola search attendees:will "transcript:async config" --output json-compact
granola digest --since 14d --limit 10 --output list

# Pull bounded context by filters or exact note IDs/Granola URLs
granola context --since 14d --limit 5 --max-bytes 20000 --redact emails,phones,secrets,attendees
granola context NOTE_ID_OR_URL --include-transcript --max-bytes 20000 --redact emails,phones,secrets,attendees
```

## Rules

- Prefer `granola context` for agent-readable bundles.
- `granola search` uses SQLite FTS5 syntax; useful fields include
  `title:`, `attendees:`, `summary_text:`, `summary_markdown:`, `folders:`,
  and `transcript:`. Combine fields to narrow searches, e.g.
  `granola search attendees:will "transcript:async config" --output json-compact`.
- Use `--redact emails,phones,secrets,attendees` unless identities are necessary.
- Include transcripts only when summaries are insufficient.
- Summarize relevant findings; do not dump large transcripts into chat.
- For filters, fields, JSON shapes, or edge cases, run `granola <command> --help`
  or `granola agent --output json-compact`.
