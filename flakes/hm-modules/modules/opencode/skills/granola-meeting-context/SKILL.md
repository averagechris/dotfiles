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
granola notes search TERMS --output json-compact --redact emails,phones,secrets,attendees
granola notes search attendees:will "transcript:async config" --output json-compact --redact emails,phones,secrets,attendees
granola digest --since 14d --limit 10 --output list

# Discover fields and compose shell pipelines
granola notes fields search --output table
granola notes fields get --output table
granola notes search renewal --fields id --limit 1 | granola notes get --fields summary --output text --redact emails,phones,secrets,attendees
granola notes search renewal --fields id --output text --limit 1 | granola notes get --fields transcript --output text --redact emails,phones,secrets,attendees

# Pull bounded context by explicit selectors: filters, exact note IDs/Granola URLs,
# --notes-file, --stdin, or --all. Do not call bare `granola context`.
granola context --since 14d --limit 5 --max-bytes 20000 --redact emails,phones,secrets,attendees
granola context NOTE_ID_OR_URL --include-transcript --max-bytes 20000 --redact emails,phones,secrets,attendees

# Read or export one note when a bundle is unnecessary
granola notes get NOTE_ID_OR_URL --output json-compact --redact emails,phones,secrets,attendees
granola notes get NOTE_ID_OR_URL --fields transcript --output text --redact emails,phones,secrets,attendees
granola export note NOTE_ID_OR_URL --format text
```

## Rules

- Prefer `granola context` for agent-readable bundles.
- `granola context` and `granola notes get-many` require an explicit selector:
  note IDs/URLs, `--notes-file`, `--stdin`, list filters such as `--since`, or
  `--all`.
- `granola notes search` searches only the local cache with SQLite FTS5 syntax;
  it is not a remote Granola API search. Useful fields include
  `title:`, `attendees:`, `summary_text:`, `summary_markdown:`, `folders:`,
  and `transcript:`. Combine fields to narrow searches, e.g.
  `granola notes search attendees:will "transcript:async config" --output json-compact`.
- Use `granola notes fields [list|search|get]` to discover valid `--fields`
  names before composing pipelines or limiting output.
- For shell pipelines, prefer `--output text` with a single field. Plain text is
  also the default for single-field row output, so commands like
  `granola notes search renewal --fields id --limit 1 | granola notes get --fields summary --output text`
  are safe.
- Use `granola notes get NOTE --output json` without `--fields` for a full note
  record. Use `--fields transcript` when transcript text is needed; v0.8 fetches
  transcript data automatically when the requested fields require it. Add
  `--no-cache` only when intentionally skipping cached reads, and
  `--no-cache-write` only when avoiding cache updates.
- Use `granola export note NOTE --format text` for single-note text export.
- Use `--redact emails,phones,secrets,attendees` unless identities are necessary.
- Include transcripts only when summaries are insufficient.
- Summarize relevant findings; do not dump large transcripts into chat.
- For filters, fields, JSON shapes, or edge cases, run `granola <command> --help`
  or `granola agent --output json-compact`.
