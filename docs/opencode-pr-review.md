# OpenCode PR Review Workflow

This repository includes repo-managed OpenCode review skills for terminal-first
pull request review.

## Goals

The design supports:

- GitHub PR review from a pasted PR URL
- reusable review logic for local diffs and patch/email-style review
- direct, concise review comments with minimal fluff
- terminal-first inspection and draft planning before posting to GitHub
- structured review artifacts that separate analysis from platform-specific
  rendering

## Design

The review workflow is intentionally split into two layers.

### Core review skill

`changes-review-core` defines the reusable review methodology.

It focuses on:

- intent vs implementation
- broader system and API implications
- security and authorization review
- data exposure in responses and logs
- code quality and repo standards
- performance, especially data access patterns and queries

It is source-agnostic and can be reused for:

- GitHub PR review
- self-review of local changes
- patch or email review workflows

The core skill now emits a **platform-neutral structured review artifact** rather
than GitHub-shaped comments. This keeps the analysis reusable across review
surfaces.

### GitHub wrapper skill

`github-pr-review` is the GitHub-specific wrapper.

It handles:

- PR URL input
- `gh`-based metadata gathering
- linked issue/ticket lookup when relevant tools are available
- default local PR checkout with revision verification unless the user opts out
- persistence of the review artifact
- terminal digest generation from that artifact
- draft review planning before posting

## Review artifact model

The review analysis is persisted with the custom `review-artifact-write` tool.

These review artifact helpers are OpenCode tools loaded by the harness, not
shell commands. Agents should call the tools directly and should not probe for
them with `type`, `command -v`, or `--help` in Bash. If the tools are missing,
the workflow should stop and report that the review tools are not loaded rather
than inventing a shell-based fallback artifact.

The preferred terminal presentation layer is the companion
`review-artifact-render` tool.

The first real draft-generation layer is `review-artifact-generate`, which takes
GitHub PR metadata plus optional local repo context and returns an artifact JSON
payload for the write tool.

v1 design choices:

- strict schema
- temporary-file storage in the system temp directory
- tool returns artifact path plus compact severity stats
- artifact source metadata should include `worktreeRoot` and/or
  `workingDirectory` when local inspection is involved so renderer excerpts are
  deterministic
- GitHub PR artifacts should also carry `owner`, `repo`, `prNumber`, `baseSha`,
  and `headSha` when available

The artifact is intended to be the source of truth for later platform-specific
rendering, such as GitHub inline comments and top-level review bodies.

Wrappers may add source-specific draft sections without changing the canonical
core findings. For GitHub, this lives under `drafts.github` and can include:

- inline comment drafts
- top-level summary bullets
- full review body draft
- recommended GitHub review state

## Generator workflow

The current intended GitHub review flow is:

1. fetch PR metadata with `gh`
2. check out the PR locally by default unless the user opts out
3. verify the local checkout matches the PR head SHA
4. fetch unified diff text with `gh pr diff`
5. generate a draft artifact JSON payload with `review-artifact-generate`
6. refine the artifact with deeper analysis as needed
7. present a human walkthrough of the changes before comment triage
8. persist it with `review-artifact-write`
9. render it with `review-artifact-render`
10. use the `functions.question` tool to triage candidate comments with the user
11. persist the triaged artifact if comments changed
12. only post after explicit confirmation using `review-github-post`

The generator is intentionally conservative:

- it drafts findings and GitHub-oriented review text
- it uses diff-derived cues to prioritize hotspots conservatively
- it derives first-pass right-side line metadata from diff hunks when possible
- it does not persist artifacts itself
- it does not post anything to GitHub

## Posting workflow

The first posting tool is `review-github-post`.

Design choices:

- requires an explicit final review state (`COMMENT`, `APPROVE`, or
  `REQUEST_CHANGES`)
- uses a single batched GitHub review submission when possible
- consumes `drafts.github` from the persisted artifact
- remains the default posting path even if the user says to post with the GitHub
  CLI, because the tool wraps `gh` and keeps posting tied to the persisted
  artifact
- if some inline drafts do not have enough location metadata for robust posting,
  they are promoted into the top-level review body rather than failing the
  entire submission

The renderer reads the persisted artifact by path and produces a default digest
view focused on:

- summary
- hotspots
- findings
- draft posting plan

v1 renderer choices:

- input is artifact path only
- default view is digest + posting plan
- posting plan is grouped by inline comments, top-level notes, and review state
- excerpts may be synthesized from recorded locations, but should remain small
- if `drafts.github` exists, renderer should prefer those precomputed drafts for
  posting-plan display

## Local checkout heuristic

The GitHub review skill should prefer local checkout by default.

Only skip local checkout when:

- the user explicitly says not to
- or checkout is unavailable / fails

When local checkout is used in a jj-managed repo, the workflow should prefer
`jj` for local inspection.

Local code should not be used as review evidence until the checked-out revision
is verified against the PR head SHA.

## Comment style

The workflow is designed for a concise, direct, casual review style.

Examples:

- `do x here`
- `y would be better if z`
- `this should enforce authz at the service layer`

The workflow should avoid praise padding or unnecessary softening.

## Review output model

The workflow drafts a full review plan before any posting action.

If the user asks to tweak wording, tone, selected comments, or final review
state after seeing the plan, update the artifact and persist it again before
posting. The persisted artifact should stay the source of truth; do not hand-roll
a separate `gh api` payload from memory.

Draft output includes:

- inline comments
- top-level review text
- a recommended review state (`comment`, `approve`, or `request changes`)
- per-comment triage status after the user has approved/refined/rejected
  candidates

The workflow should default to drafting **comments**, and should not choose or
submit a final review state without explicit user confirmation.

## Comment triage loop

After the digest and draft posting plan are ready, the workflow should use the
`functions.question` tool to work through candidate comments with the user.

This loop is for review triage, not workflow debugging.

Before this loop, the workflow should present a compact walkthrough of the PR so
the user understands the change before approving comments. The walkthrough should
cover the change story, file tour in execution/dependency order, main data or
control flow, behavior surface, test confidence, and suggested follow-up deep
dives.

Typical outcomes per comment:

- approve as-is
- refine wording
- change severity or final review-state impact
- convert between inline and top-level
- reject/drop
- hold for later

For each candidate comment, show the target location, exact body, severity,
one-sentence rationale, and proposed final-state impact. Keep a running summary
of approved, edited, dropped, and held comments. If any triage decision changes
the posting plan, persist a fresh artifact before posting.

## Suggestion blocks

For small, concrete, low-risk fixes, the workflow should prefer GitHub
suggestion blocks to make nit comments easier to apply.

## Terminal-first UX

The first implementation focuses on a structured terminal digest rather than a
custom HTML view.

If a PR already contains a link to an existing explainer artifact, the workflow
should surface it as supplemental context, but the review flow itself remains
terminal-native.

To keep token usage under control, the terminal digest should stay compact:

- summarize findings
- reference file paths and line ranges
- avoid dumping large code excerpts or duplicating diff content
- allow only small selected excerpts when especially useful

## Hotspot prioritization

The GitHub wrapper should triage mixed PRs instead of reading every changed file
with equal attention.

Priority order:

1. domain and behavior-changing code
2. authz, validation, and endpoint-layer logic
3. repositories, queries, and migrations
4. API/schema compatibility surfaces
5. tests
6. docs and chore files
