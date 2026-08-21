---
name: interrogate-me
description: Use only when the user explicitly asks to run this skill. Never load it autonomously. Runs independent read-only reviews and returns a lead verdict without fixes.
---

# Interrogate me

Stress-test a change with independent reviewers, then make a lead judgment. Give every reviewer the same intent, scope, prompt, and rubric. Return a verdict. Never apply fixes automatically.

## Set the scope

Use files or diffs named by the user. Otherwise identify the relevant change with the repository's configured VCS. Prefer `jj` in jj repositories. Use Git in Git-only repositories. Do not alter VCS state or inspect unrelated parent changes.

Include enough surrounding code to trace behavior. Never inspect `secrets/`, decrypted secret material, `.age` files, credentials, or authentication material. Exclude them from the review even if they appear in a diff.

## State the intent

Write one short paragraph describing what the change should accomplish. Derive it from the user request, change or commit descriptions, PR text, docs, and code. Ask a question only when material ambiguity would invalidate the review. Otherwise state your interpretation and continue.

## Choose reviewers

Load and use the `subagent-selection` skill before choosing reviewers. Its rendered policy and scorecard are canonical. Do not reconstruct its table or tier definitions here. Choose the reviewer count and tiers by consequence, residual uncertainty, capability, and cost. Treat the scorecard as descriptive, not as a ranking to maximize intelligence.

Fully mechanical, machine-checked work may need no delegated review. A normal request usually gets two independent reviews when the second pass adds signal. Two passes at the same tier are independent runs, not model-family diversity. Follow the canonical policy for tier boundaries, escalation, review limits, and finding gates. Invoking this skill does not by itself raise the change's risk.

Fill the [reviewer prompt template](references/reviewer-prompt-template.md) with the stated intent, exact scope, and the complete [review rubric](references/review-rubric.md). Send the identical filled prompt to every reviewer. Launch all reviewers in one task-tool message so they run in parallel. Every handoff must say: complete the review directly, do not delegate, do not edit, and do not use `opencode run`.

Reviewers are behaviorally read-only. They may inspect allowed code and run safe read-only checks. They must not edit files, change VCS state, commit, push, post comments, or mutate external systems.

## Verify and synthesize

Read every finding and verify it against the code. Merge duplicates, name which reviewers raised each one, and preserve explicit disagreements. Agreement is useful evidence, not proof. A lone finding can still expose a serious bug.

Apply the canonical severity policy from `subagent-selection`. Do not let low-severity findings or nits expand the work automatically. Reject style preferences, speculative edge cases without a reachable path, and rewrite requests that show no concrete problem. An empty review is valid.

Use the [lead judgment framework](references/lead-judgment.md) to place every finding in **Act on**, **Consider**, **Noted**, or **Dismissed**. Never fix findings as part of this skill.

## Return the verdict

Use this structure:

### Intent

The stated intent and any interpretation you made.

### Scope and reviewers

List the reviewed files or diff, excluded material, each reviewer tier, and finding count.

### Act on

Verified findings that should block the change.

### Consider

Real concerns whose benefit may not justify the cost now.

### Noted

Valid, low-priority observations.

### Dismissed

Rejected findings with a short reason.

### Agreement and disagreement

Say where reviewers converged or differed and what you verified. For each retained finding, include severity, file and line or symbol, behavior path, evidence, consequence, reviewers, and a suggested direction only when justified.
