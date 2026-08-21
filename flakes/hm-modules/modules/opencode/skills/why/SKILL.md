---
name: why
description: "Use for design rationale, regressions, postmortems, data-backed thresholds, and questions such as 'why does X work this way?' Discovers available evidence categories, searches each in parallel, and returns a cited account of decisions and tradeoffs. Use how for runtime behavior."
---

# Why

Investigate why code has its current shape. Find the constraints, edge cases, alternatives, and history behind it. The `how` skill explains mechanics. This skill explains intent.

## Rules

- Gather evidence before forming a story.
- Cite claims about intent with a commit, PR, ticket, document, telemetry item, or code comment. Code mechanics alone do not prove intent.
- Keep contradictions visible.
- Treat the user's suggested reason as a hypothesis to test.
- Report unavailable sources and null searches. Absence is not proof that a record never existed.
- Match wording to confidence. Do not trade accurate hedges for a smoother answer.
- Never inspect secrets, credentials, authentication material, decrypted secret material, or `.age` files.

Use the Direct, Supported, Inferred, Speculative, and Unknown tiers in `references/epistemics.md`.

## 1. Define the target and question

Identify the code, pattern, feature, or decision in question. Decide whether the user asks about rationale, an alternative, an edge case, an external constraint, continued existence, or broad history.

If the target is vague, infer it only from the conversation and available editor context. State your interpretation, then proceed so the user can correct it.

## 2. Build a code anchor

Collect:

- file paths and line ranges
- key symbols
- recent and older commits that shaped the target
- PR numbers, ticket IDs, and incident IDs in those commits

Use the repository's configured VCS. Prefer `jj` in a jj repository. Check local VCS skill instructions or command help for attribution, rename-aware history, patches, and descriptions.

When `gh` is available, retrieve substantive PR context:

```bash
gh pr view <number> --json title,body,author,createdAt,mergedAt,labels,closingIssuesReferences,comments,reviews
```

Pass this anchor to every investigator.

## 3. Discover and search available categories

Inspect the tools, skills, CLIs, and integrations available now. Do not assume an integration exists or inspect credentials to enable it. Map capabilities to these six categories:

1. Source control history
2. Issue or ticket tracking
3. Long-form documents
4. Infrastructure observability
5. Error or exception tracking
6. Product analytics warehouse

Source control is available through the repository, though a forge may not be. Use skill instructions, command help, and integration descriptions to classify other capabilities. Choose the primary category for ambiguous tools and note the ambiguity.

In this setup, search repository Markdown first for current decisions and specs. Search Linear for current product and project context. Use Notion for old RFCs and PRDs from the pre-AI era, or when the user points to Notion. Do not treat an old Notion page as current without corroboration.

Launch one investigator per available category in one message. Never combine categories in one investigator. Each investigator stays read-only and receives:

1. `references/investigator-prompt-template.md`, with all placeholders filled
2. the matching file under `references/sources/`, adapted to the available interface
3. `references/sources/incident-postmortem.md` when the code looks defensive
4. the code anchor
5. the original question

For current repository Markdown, search the repository directly. `references/source-playbook.md` indexes the examples.

### What each category contributes

- **Source control history.** Always search it. Commits, PR discussions, comments, tests, and co-changes can preserve implementation-time rationale.
- **Issue or ticket tracking.** Tickets, parents, projects, comments, and labels often hold customer, product, deadline, or compliance reasons.
- **Long-form documents.** Current repository Markdown can hold problem statements, alternatives, ADRs, strategy, and postmortems. Old Notion RFCs and PRDs may preserve earlier decisions. Search other Notion material when the user points to it.
- **Infrastructure observability.** Metrics, monitors, logs, traces, and incidents show runtime conditions around a change.
- **Error or exception tracking.** Issues, events, stack traces, and releases can connect defensive code to a failure.
- **Product analytics warehouse.** Events, experiments, usage, query history, and distributions show user or data conditions around a change.

### Skips, gaps, and follow-up

Skip a category only when no matching capability is available or the source is provably irrelevant. For example, error tracking is irrelevant to a build-time script with no runtime path. "This probably is not an error-tracking issue" is not enough. Record every skip in the final coverage map.

A null search is useful only with its query, scope, time range, access, retention, and indexing limits. It does not prove nonexistence. An inaccessible or expired record is a gap, not a null result.

First-wave investigators cannot use each other's leads. They record cross-source references under Additional Leads. After they return, follow each material lead with the matching investigator or tool. Keep this pass bounded. Skip duplicate, immaterial, inaccessible, or out-of-scope leads with a reason.

Only answer inline for a trivial, single-commit target after confirming that every available category would add nothing. State that decision. This should be rare.

## 4. Synthesize

Launch one read-only synthesizer with:

1. all findings, null results, follow-up results, and justified skips
2. the code anchor
3. the original question
4. the full text of `references/epistemics.md` in `{EPISTEMICS_FRAMEWORK}`
5. `references/synthesizer-prompt-template.md`, with every placeholder filled

The synthesizer may spot-check citations with available tools. It must separate evidence from inference and retain contradictions and gaps.

## 5. Present and verify

Lightly edit the result for clarity, but do not strengthen its confidence wording. Before responding, verify citations and use this structure:

- **The question.** A concise restatement.
- **The code in question.** Paths, lines, and symbols.
- **What we found.** Direct and Supported claims with citations.
- **What we can reasonably infer.** Inferred claims with explicit reasoning and hedged wording.
- **Competing hypotheses.** Speculative alternatives, evidence for each, and missing or contrary evidence. Omit when one answer is well supported.
- **What we don't know.** Unanswered questions, null searches, and unavailable sources.
- **Sources consulted.** One line per category, including empty and skipped searches.
- **Confidence summary.** Overall calibration.

Format coverage lines as:

`- <category and tool>: <search scope>. <finding, "no relevant results," or "skipped" with reason>.`

If the investigation precedes a code change, finish with Preserve, Change, Avoid, and Risk constraints for planning.

## Final audit

Check that:

- every Direct or Supported claim has a verified citation
- every Inferred or Speculative claim uses matching language
- no claim uses code mechanics as proof of intent
- the user's hypothesis was tested rather than accepted
- contradictions remain visible
- gaps, null searches, and skips include concrete scope
- all six categories appear in the coverage map

## References

- `references/epistemics.md`: confidence tiers and wording
- `references/investigator-prompt-template.md`: investigator prompt
- `references/source-playbook.md`: category playbook index
- `references/sources/*.md`: source-specific search guidance
- `references/synthesizer-prompt-template.md`: synthesizer prompt and output
