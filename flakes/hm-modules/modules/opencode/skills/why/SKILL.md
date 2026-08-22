---
name: why
description: "Use for design rationale, regressions, postmortems, data-backed thresholds, and questions such as 'why does X work this way?' Starts with current code, docs, and linked history, then follows relevant evidence leads to a cited account of decisions and tradeoffs. Use how for runtime behavior."
---

# Why

Investigate why code has its current shape. Find the constraints, edge cases, alternatives, and history behind it. The `how` skill explains mechanics. This skill explains intent.

## Rules

- Gather evidence before forming a story.
- Cite claims about intent with a commit, PR, ticket, document, telemetry item, or code comment. Code mechanics alone do not prove intent.
- Keep contradictions visible.
- Treat the user's suggested reason as a hypothesis to test.
- Report relevant unavailable sources and null searches. Absence is not proof that a record never existed.
- Match wording to confidence. Do not trade accurate hedges for a smoother answer.
- Never inspect secrets, credentials, authentication material, decrypted secret material, or `.age` files.

Use the Direct, Supported, Inferred, Speculative, and Unknown tiers in `references/epistemics.md`.

## 1. Define the target and question

Identify the code, pattern, feature, or decision in question. Decide whether the user asks about rationale, an alternative, an edge case, an external constraint, continued existence, or broad history.

If the target is vague, infer it only from the conversation and available editor context. State your interpretation, then proceed so the user can correct it.

## 2. Build a code anchor

Collect file paths and lines, key symbols, commits that shaped the target, and any linked PR, ticket, document, or incident IDs. Use the repository's configured VCS and prefer `jj` in a jj repository. Consult local VCS guidance for attribution, rename-aware history, patches, and descriptions.

When a forge is available and a linked change appears material, retrieve its substantive description, discussion, reviews, and linked records with the appropriate read-only tool. Do not assume a particular forge.

## 3. Follow relevant evidence

Start with current code and repository documentation, then inspect VCS history and records linked from commits, comments, or docs. These sources establish the target and usually reveal the vocabulary, dates, and IDs needed for precise follow-up.

Search other sources only when a lead names them or when that source could plausibly decide between competing rationales. Depending on the question, useful evidence may include issue trackers, design documents, meeting notes, CI records, observability, error tracking, product analytics, or incident records. Inspect available tools and skill instructions without assuming an integration exists or inspecting credentials to enable it.

Direct investigation and synthesis are the default. When evidence volume or independent investigation justifies delegation, load `subagent-selection` and assign focused, non-overlapping sources or questions. Each investigator stays read-only and receives:

1. `references/investigator-prompt-template.md`, with its placeholders filled
2. applicable guidance from `references/source-playbook.md`
3. `references/sources/incident-postmortem.md` when the target looks defensive and incident evidence is plausible
4. the code anchor
5. the original question

Search repository Markdown directly. Use agent history only after normal searches or to recover missing links, and verify its leads against a first-class source. The source playbook provides generic, conditional examples rather than required coverage.

### What sources can contribute

- **Source control and linked changes.** Commits, reviews, tests, co-changes, and CI can preserve or corroborate implementation-time rationale.
- **Trackers and documents.** Tickets, ADRs, RFCs, meeting notes, and postmortems can state product constraints, alternatives, or deadlines.
- **Operational evidence.** Logs, metrics, traces, incidents, exceptions, and product data can establish the runtime or usage conditions around a decision.

### Gaps and follow-up

Do not perform ceremonial searches. Record why a promising lead was not followed, but do not list unrelated source categories merely to prove coverage.

A null search is useful only with its query, scope, time range, access, retention, and indexing limits. It does not prove nonexistence. An inaccessible or expired record is a gap, not a null result.

Follow material leads with the matching tool or a focused investigator. Keep follow-up bounded. Skip duplicate, immaterial, inaccessible, or out-of-scope leads with a reason.

## 4. Synthesize

Synthesize directly by default. If the evidence set is too large or contradictory for reliable synthesis in the current context, load `subagent-selection` and give one read-only synthesizer:

1. all findings, null results, follow-up results, and justified unfollowed leads
2. the code anchor and original question
3. the full text of `references/epistemics.md`
4. `references/synthesizer-prompt-template.md`, with every placeholder filled

Separate evidence from inference. Retain contradictions and gaps. Any synthesizer may spot-check citations with available read-only tools.

## 5. Present and verify

Before responding, verify citations and adapt this structure to the evidence:

- **The question.** A concise restatement.
- **The code in question.** Paths, lines, and symbols.
- **What we found.** Direct and Supported claims with citations.
- **What we can reasonably infer.** Inferred claims with explicit reasoning and calibrated wording.
- **Competing hypotheses.** Speculative alternatives, evidence for each, and missing or contrary evidence. Omit when one answer is well supported.
- **What we don't know.** Unanswered questions, relevant null searches, and unavailable sources.
- **Sources consulted.** Searches that informed the answer, including relevant null searches and justified unfollowed leads.
- **Confidence summary.** Overall calibration.

For each source, name the tool or record, search scope, and finding or limit. If the investigation precedes a code change, finish with Preserve, Change, Avoid, and Risk constraints for planning.

For a postmortem, preserve the same epistemic discipline while also distinguishing trigger, contributing conditions, detection, response, impact, and corrective actions. Do not let temporal correlation become causation.

## Final audit

Check that:

- every Direct or Supported claim has a verified citation
- every Inferred or Speculative claim uses matching language
- no claim uses code mechanics as proof of intent
- the user's hypothesis was tested rather than accepted
- contradictions remain visible
- gaps and null searches include concrete scope
- searches stayed relevant to the question and material leads

## References

- `references/epistemics.md`: confidence tiers and wording
- `references/investigator-prompt-template.md`: focused investigator prompt
- `references/source-playbook.md`: optional source guidance
- `references/sources/*.md`: source-specific search guidance
- `references/synthesizer-prompt-template.md`: optional synthesis prompt and output
