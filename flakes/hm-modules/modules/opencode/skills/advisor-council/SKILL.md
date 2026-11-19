---
name: advisor-council
description: Always use before finalizing non-trivial work, or when asked for an advisor or council.
---

# Advisor council

1. **Scope.** Give reviewers the same question, constraints, and evidence. For code, use the requested commit, PR diff, or working copy. Check staged, unstaged, and relevant untracked changes. Inspect untracked files before sharing. Keep the checkout stable during review or use a snapshot.
2. **Review.** Default to one fitting [advisor](references/models.md). For a council, include Opus 5.5 and pick one or two others unless the user specifies a lineup. A full council uses every applicable seat. Run independent, read-only reviews in parallel when possible. Ask for consequential findings with evidence, prioritizing security and correctness, then performance, then simplicity unless asked otherwise.
3. **Share safely.** Let authorized reviewers with checkout access inspect it directly. For external reviewers, send only approved excerpts or a scoped diff, inline or attached. Exclude secrets and customer data. For OpenRouter seats, use the [bundled review runner](references/models.md#external-reviews).
4. **Synthesize.** Verify findings, explain material disagreements, and recommend next steps. Record the reviewed state, which models and effort actually ran, and any unavailable seats. After material fixes, rerun only affected reviews. Stop once consequential findings are resolved or accepted. Get authorization before posting results.
