# Synthesizer prompt template

Fill every placeholder.

---

Answer a "why" question by weighing the relevant evidence supplied below. Separate evidence from inference. Keep contradictions and gaps visible.

## Question

> {QUESTION}

## Code anchor

**Target files and lines:** {FILES_WITH_LINE_RANGES}

**Key symbols:** {SYMBOLS}

## Findings

{ALL_INVESTIGATOR_FINDINGS}

## Skipped sources

{SKIPPED_SOURCES_WITH_REASONS}

## Epistemics framework

Follow this supplied framework in full:

{EPISTEMICS_FRAMEWORK}

Every claim must be Direct, Supported, Inferred, Speculative, or Unknown. Direct and Supported claims need citations. Inferred and Speculative claims need hedged wording and an explicit reasoning chain. Code mechanics do not prove intent. Empty searches do not prove nonexistence. Test any hypothesis in the user's question.

## Work

1. Read every finding, including null results and follow-up results.
2. Merge duplicate references without losing distinct evidence.
3. Show disagreements instead of choosing the easiest narrative.
4. Assign each claim a confidence tier and matching wording.
5. Spot-check citations with available read-only tools when needed.
6. Leave unresolved questions open.
7. Exclude agent-history conclusions unless an authoritative source verifies the claim. Keep unverified `ctx` results as leads or gaps.

Do not write files or modify external state. Never inspect `secrets/`, decrypted secret material, `.age` files, credentials, or authentication material.

## Output

Use these headings.

### The question

Restate it in one or two sentences.

### The code in question

Give paths, lines, and symbols.

### What we found

List cited `[Direct]` and `[Supported]` claims. Direct evidence explicitly states the reason. Supported evidence combines multiple indirect facts.

### What we can reasonably infer

List `[Inferred]` claims. Show the evidence and inference step. Use calibrated language. Omit this section if empty.

### Competing hypotheses

For each `[Speculative]` hypothesis, list evidence for it and contrary or missing evidence. Omit this section when one answer is well supported.

### What we don't know

Name unanswered questions, exact null searches, unavailable sources, and limits such as access or retention. Suggest a person to ask only when evidence identifies one.

### Sources consulted

List each source actually consulted. Name the tool, queries or items, time windows, results, and relevant null searches or unfollowed leads. For warehouse findings, include fully qualified tables and compact numeric summaries.

### Confidence summary

Summarize which rationale is established, inferred, speculative, or unknown in one or two sentences.

## Final check

- Verify every Direct and Supported citation.
- Match wording to each tier.
- Remove code-as-intent claims.
- Keep contradictions.
- Include concrete gaps, null searches, and skips.
- Confirm that the user's hypothesis was tested.
