# Investigator prompt template

Fill every placeholder. Append the playbooks relevant to the focused source or question. If the target looks defensive and incident evidence is plausible, also append `sources/incident-postmortem.md`.

---

Investigate a focused source or question about the history of a piece of code. Stay within the assignment and return evidence for the caller's synthesis, not a final story.

Be exact. Quote important wording and provide a citation that can be checked quickly. Search broadly before narrowing. Read full items, including comments and linked items within your category. Record contradictions, queries, null results, access limits, and retention limits.

Never infer intent from code mechanics. Never invent or round partial evidence into certainty. Redact credentials, tokens, cookies, personal data, and sensitive payloads as `[REDACTED]` while retaining enough non-sensitive context and the citation.

## Question

> {QUESTION}

## Code anchor

**Target files and lines:** {FILES_WITH_LINE_RANGES}

**Key symbols:** {SYMBOLS}

**Initial commits, newest first:**
{COMMIT_LIST}

**PR numbers:** {PR_NUMBERS}

**Ticket IDs:** {TICKET_IDS}

## Assigned source

{SOURCE_NAME}

{SOURCE_PLAYBOOK_SECTION}

## Instructions

Use only available OpenCode tools, skills, CLIs, and integrations. Read the applicable skill or command help instead of assuming a schema. Do not inspect `secrets/`, decrypted secret material, `.age` files, credentials, or authentication material. Report unavailable or unauthenticated sources as gaps.

1. Start with broad searches, then inspect relevant items deeply.
2. Read full PRs, tickets, documents, threads, or telemetry records.
3. Follow links within your assigned category. Record cross-category links under Additional Leads. Do not chase them.
4. Capture exact quotes when wording matters. Include IDs, URLs, hashes, file lines, authors, and dates when available.
5. Record exact searches that returned nothing and their scope.
6. Preserve conflicting evidence and plausible alternative readings.
7. Treat `ctx` results only as leads. Verify them against a source in the assigned category before reporting a claim.

Do not substitute evidence about a nearby feature for the target. Do not answer the overall question.

## Return format

### Source

Name the category and tool or integration.

### Searches

List exact queries, time ranges, items opened, and relevant access, indexing, or retention limits.

### Direct evidence

For each item, return the quote or faithful paraphrase, citation, author and date when available, and one sentence about relevance.

### Indirect evidence

For each item, return the fact, citation, inference it may support, inference chain, and alternative readings.

### Contradictions

List disagreeing items with both citations. Write "None found" if applicable.

### Gaps

List unanswered questions, null searches with scope, and unavailable records. An empty search does not prove nonexistence.

### Additional leads

List exact cross-category references for the parent's bounded follow-up. Write "None" if applicable.
