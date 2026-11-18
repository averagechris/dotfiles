---
name: advisor-council
description: Always use for non-trivial work to collect independent feedback, or when asked for an advisor or council.
---

# Advisor council

1. **Scope.** Give reviewers the same question, constraints, and evidence. For code, use the requested commit, PR diff, or working copy. Include relevant staged, unstaged, and untracked changes. Keep the reviewed state stable until reviews finish or share a snapshot.
2. **Review.** Use one fitting [advisor](references/models.md) for focused feedback. For a council, include Opus 5.5 and pick one or two others unless the user specifies a lineup. A full council uses every applicable seat. Run independent, read-only reviews in parallel when possible. Ask for consequential findings with evidence, prioritizing security and correctness, then performance, then simplicity unless asked otherwise.
3. **Share safely.** Let authorized reviewers with checkout access inspect it directly. For external reviewers, send only approved excerpts or a scoped diff, inline or attached. Exclude secrets and customer data. See [how to run an external review](references/models.md#external-reviews).
4. **Synthesize.** Verify findings, explain material disagreements, and recommend next steps. Record the reviewed state, which models and effort actually ran, and any unavailable seats. Re-review material changes when needed. Get authorization before posting results.
