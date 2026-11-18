---
name: advisor-council
description: Get independent model feedback on a plan, architecture, change, or draft and synthesize it with verified evidence. Use when Chris asks for a council, named outside-model advisors, or an independent taste consultation.
---

# Advisor council

1. **Frame the question.** State the decision, constraints, options, and what the reviewer should check. Pin a code review to a commit or diff. Prioritize security and correctness, then performance, then simplicity and maintainability unless Chris gives a different order.
2. **Choose advisors.** Read [the roster](references/models.md). Include Opus 5.5 unless Chris explicitly opts out. Use other requested seats, or select a small number that fit the task. A single taste consultation can use the requested advisor. A full council attempts every applicable configured seat.
3. **Send one compact evidence packet.** Include only what each destination is authorized to receive. Confirm permission for private material and review provider terms applicable to it. Strip credentials, customer data, and irrelevant internal context. Keep the evidence and questions consistent across reviewers. Give each reviewer a fresh, independent session with analysis-only instructions, without other reviewers' conclusions. Run independent calls in parallel when available.
4. **Verify.** Ask for a short recommendation, consequential findings with evidence, and what remains unproven. Check claims against the source or a focused test. Distinguish observed defects from assumptions, design preferences, and unresolved disagreements.
5. **Synthesize.** Lead with a recommendation and the few points that could change the decision. Name each advisor that actually ran, its model and effort, the revision reviewed, and any unavailable seats. Provide deeper evidence or individual reports when requested. Re-review the affected area after a material change. The lead owns the decision and this workflow does not publish feedback or modify the work.

## Running a review

Verify the selected executor, CLI version, provider, exact model, and reasoning variant before relying on a reviewer. OpenCode v2 lists available models with `opencode models --standalone`. A cold catalog can be empty while providers initialize. Check it again or use the model picker. When auth or routing is unproven, use a tiny synthetic prompt with no work material and check the returned model and variant. A public catalog listing does not prove your account can run it.

For OpenCode, put only the approved packet in a fresh scratch directory. Run from that directory with tool permissions denied and keep the installed OpenCode credentials local to the executor. Use `--standalone` so the restriction applies to the new server. Never use `--auto` for a review.

```sh
OPENCODE_CONFIG_CONTENT='{"permissions":[{"action":"*","resource":"*","effect":"deny"}]}' \
opencode run --standalone \
  --model 'openrouter/anthropic/claude-opus-5.5#high' \
  --file ./packet.md \
  'Review the attached packet independently. Give a recommendation and evidence for material findings. Analysis only. Do not use tools, edit, or delegate.'
```

Use a clean OpenCode configuration with only the intended provider. Before submitting a packet, check for custom agents, plugins, integrations, instructions and references that could add context or permissions. A prompt restriction alone is not an isolation boundary.

Cloud and Dot sessions need a usable shell executor, a local OpenCode installation, and their own provider access. They do not inherit suremac's tools or credentials. Check the published environment's configured tools path first. In a Dot workspace with a shared install, also check `/workspace/shared/cloud-tools/bin/opencode`. If a seat cannot run, report the blocker. Never present a replacement or catalog entry as a completed review.
