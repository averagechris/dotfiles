# Epistemics

Code shows mechanics, not intent. Historical evidence is partial and may conflict. Classify every claim below and match its wording to its evidence.

## Confidence tiers

### Direct

A source explicitly states the reason. Examples include a PR that names the bug, a ticket that names a customer need, a comment that explains a limit, or an ADR that rejects an alternative.

Use plain causal wording such as "This exists because X" and cite the source next to the claim.

### Supported

Several indirect facts converge, but no source states the reason. A performance PR title, a `perf` ticket label, and changes to the same hot path may jointly support a performance rationale.

Say "The evidence points strongly to X" and cite each fact.

### Inferred

The context supports a reasonable interpretation without explicit confirmation. State the chain: "Given A and B, C appears likely; D supports that reading." Use "appears," "likely," "suggests," "is consistent with," or "one reading is."

### Speculative

The hypothesis is plausible, but evidence is thin or competing explanations fit. Say "One possibility is X, but we found no direct evidence." Put it with competing hypotheses.

### Unknown

The searches did not answer the question. Name the sources, exact queries, scope, and limits. Do not turn an empty search into proof that no record exists.

## Calibration rules

Words such as "because," "the reason is," "was designed to," "fixes," and "the team decided" claim explicit causality or intent. Use them only for Direct claims with adjacent citations. Use strong but non-causal language for Supported claims.

Do not use "obviously," "clearly," "of course," or dismissive "just." Do not hide inference behind "I think." Name the evidence instead.

Do not retrofit a clean reason because current code makes sense. A copied pattern may be accidental. An old reason may no longer apply. Missing security discussion does not show that security was irrelevant.

## Test user hypotheses

If the user asks, "I assume this is for performance?", treat performance as one candidate. Search independently. Confirm, reject, or leave it open based on evidence.

## Keep contradictions

If a ticket says a customer requirement drove the work while the PR calls it tech debt, report both. They may describe different parts of the history. Do not choose the tidier version.

## Name missing evidence

For each gap, state the unanswered question, sources and queries searched, scope or time range, and any tangential result. Suggest a person to ask only when the record identifies one.

## Final calibration check

1. Does every Direct or Supported claim have a citation?
2. Does wording match the tier?
3. Is code being used as proof of its own intent? If so, remove or reclassify the claim.
4. Are contradictions visible?
5. Does What We Don't Know name concrete gaps and search limits?
