---
name: granola-meeting-context
description: Retrieve past Granola meetings to clarify requirements, decisions, follow-ups, or whether work matches a prior conversation.
---

# Granola Meeting Context

Use `granola agent --output json-compact` and command `--help` for CLI guidance.
Search for candidates first, bounded by topic, participants, and dates; retrieve
only relevant notes. Search uses the local cache, so missing results may require
a bounded sync. Transcript search requires notes cached with transcripts.

Prefer summaries; fetch raw transcripts when wording, disagreement, or missing
detail matters. Keep bundles small with `granola context --limit` and
`--max-bytes`, using explicit IDs/URLs or date filters. Redact unnecessary
personal data with `--redact emails,phones,secrets,attendees`.

Cite meeting titles, dates, and stable IDs or links. Distinguish transcript
evidence from generated summaries and corroborate approval or implementation
against project artifacts. Summarize findings instead of dumping transcripts.
