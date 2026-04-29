---
name: github-pr-review
description: Review GitHub pull requests from a PR URL using gh, with a terminal-first digest and draft comments built on the shared changes review workflow.
---

# GitHub PR Review

Use this skill when the user wants to review a GitHub pull request, usually by
pasting a PR URL.

This skill is a GitHub-specific wrapper around `changes-review-core`.

## Design choices

- Accept a GitHub PR URL as the normal entry point.
- Use the `gh` CLI for GitHub metadata and review actions.
- Keep the workflow terminal-first.
- Surface any existing PR explainer link when present, but do not depend on it.
- Include a reviewer-oriented walkthrough that helps the user understand the
  changes before asking them to approve or post comments.
- Draft comments first and only post when explicitly requested.
- Default to local PR checkout unless the user explicitly says not to.
- Treat `review-artifact-generate`, `review-artifact-write`,
  `review-artifact-render`, and `review-github-post` as OpenCode tools, not
  shell commands.
- When local checkout is used in a `jj` repo, prefer `jj` for local change
  inspection and branch/bookmark workflows.
- Only treat local code as review evidence after verifying that the checked-out
  revision matches the PR head SHA.

## Inputs

Normal input:

- a GitHub PR URL

Useful optional input:

- whether to perform local checkout
- whether to prepare posting output only or also publish
- whether to emphasize particular concerns

## High-level workflow

1. Parse the PR URL.
2. Use `gh` to fetch PR metadata and changed-code context.
3. By default, attempt to check out the PR locally unless the user explicitly
   opts out.
4. Verify the local checkout against the PR head SHA before using local reads as
   review evidence.
5. Prefer generating a draft artifact JSON payload with
   the `review-artifact-generate` tool when the necessary PR metadata is
   available.
   Provide diff text as well so the generator can use conservative diff-derived
   cues rather than only file lists, including first-pass right-side line
   mapping from diff hunks for inline draft fidelity.
6. Gather intent context from:
   - PR title
   - PR body
   - linked issue or ticket references when available
   - commit history and commit messages
7. Detect whether the PR body includes a link to an existing PR explainer or
   similar review artifact and surface it in the digest.
8. Inspect locally using repo-native tools, preferring `jj` when the local repo
   is jj-managed.
9. Use remote GitHub metadata and diff as supporting context and as a cross-check
   against local evidence.
10. Apply `changes-review-core` to refine or fill gaps in the generated artifact
   when needed.
11. Produce a human change walkthrough before comment triage so the user can
    understand the PR rather than only seeing defects.
12. Persist the structured review artifact via the `review-artifact-write` tool.
13. Build a compact terminal digest and draft posting plan from the artifact via
    the `review-artifact-render` tool.
14. After evidence is stable, the walkthrough is presented, and the digest is
    ready, use the `functions.question` tool to work through candidate comments
    with the user.
15. Only if explicitly requested after that review loop, publish the review with
     the `review-github-post` tool, passing an explicit final review state.

### Tool invocation rule

The review artifact helpers are OpenCode tools exposed by the harness. They are
not binaries on `$PATH`.

- Do not check them with `type`, `command -v`, or `--help` in a shell.
- Do not replace them with hand-written JSON files or direct `gh api` payloads
  unless the user explicitly says not to use the tool.
- If a required review tool is not available in the current harness, stop and
  report that the review tools are not loaded. Continue only if the user asks
  for a degraded manual review.

## GitHub context to gather

Use `gh` to gather, at minimum:

- PR title and body
- PR author
- PR number
- base and head refs
- base and head SHAs
- changed files
- commits
- diff / patch context
- existing review state and discussion context when relevant

When available, also gather linked issue or ticket references. If the issue
system appears to be Linear or another supported tracker and the relevant tools
or skills are available, use them to verify that the implementation matches the
intended scope.

## Local checkout heuristic

Default to local checkout first.

Only skip local checkout when:

- the user explicitly says not to
- or the repo is unavailable / checkout fails

If local checkout fails or is unavailable, continue in explicit remote-only
degraded mode.

If local checkout is used:

- prefer `jj` in jj-managed repos
- use local diff/log/show tools to inspect context more deeply
- avoid mutating VCS state more than needed for inspection

### Evidence integrity rule

Local code is the preferred source of truth for review, but only after
verification.

Before using local files as evidence for findings:

- verify the local repo matches the PR repo
- verify the checked-out revision matches the PR `headSha`

If that verification fails:

- do not use local reads to support findings
- fall back to explicit remote-only/degraded mode
- clearly tell the user that confidence is lower until checkout is corrected

## Hotspot prioritization

Do not review all changed files equally.

Prioritize in this order:

1. core behavior and domain logic
2. endpoint validation, serialization, and authz enforcement
3. persistence, queries, and migrations
4. API schema changes with compatibility implications
5. tests that validate the behavioral changes
6. docs and chore files

Use docs, tests, and schema snapshots to confirm intent and coverage, but do
not let them crowd out review attention on the code paths that actually carry
behavioral, security, or performance risk.

## Artifact-first output

The primary analysis output should be a structured review artifact, not a long
chat transcript.

Use `review-artifact-write` to validate and persist the artifact, then use that
artifact as the source of truth for the digest and any later posting flow.

When available, use `review-artifact-generate` to create the initial artifact
payload from the PR metadata, diff text, and optional local repo context. Treat
that output as a draft that the agent may refine based on deeper review.

When local inspection is used, include `worktreeRoot` in the artifact source
metadata so `review-artifact-render` can synthesize small excerpts from recorded
locations deterministically.

Prefer `review-artifact-render` as the terminal presentation layer for the
default digest view.

The writer tool returns:

- artifact path
- compact stats by severity

Then use `review-artifact-render` with the artifact path to render the digest.
Use those results in the transcript instead of reprinting the full artifact.

For GitHub PRs, enrich the artifact source metadata with PR-specific fields and,
when useful, add `drafts.github` so the wrapper can persist precomputed inline
comment drafts and top-level review text derived from the findings.

## Terminal-first output

Always produce a structured terminal digest before any posting step.

### Change walkthrough

Before comment triage, explain the PR in a way that helps the user build a
mental model of the changes. This is separate from findings and should not be a
long code dump.

Use this shape:

1. **Change story** — one short paragraph explaining the problem being solved
   and the implementation strategy.
2. **Review-order file tour** — 3-8 bullets in dependency or execution order,
   not alphabetical order. For each hotspot, say why it matters and what changed
   there.
3. **Data/control flow** — trace the important request, CLI command, API call,
   background job, or state transition through the changed files.
4. **Behavior surface** — call out user-visible behavior, API contracts,
   schema changes, migrations, authz boundaries, or operational implications.
5. **Tests and confidence** — what tests or existing patterns reduce risk, and
   what remains unproven.
6. **Suggested deep dives** — 2-5 concrete follow-up questions the user can pick
   from, such as “walk me through the auth path” or “show why this line is
   risky”.

Keep it compact by default. If the user asks to understand a specific area,
pause the review flow and drill into that area before finalizing comments.

### Terminal digest sections

1. **PR summary**
   - title
   - repo
   - author
   - base/head
   - linked issue/ticket references

2. **Intent summary**
   - what the PR claims to do
   - any mismatch risk between stated intent and implementation

3. **Change hotspots**
   - high-risk files or areas
   - files likely to deserve inline comments

4. **Review findings**
   - grouped by severity and target
   - reference file paths and line ranges
   - avoid large code dumps
   - allow small selected excerpts only when especially useful

5. **Draft posting plan**
    - proposed inline comments
    - proposed top-level review text
    - recommended review state: `comment`, `approve`, or `request changes`
    - reminder that final review state must be confirmed by the user
    - current per-comment triage state when comment triage has already happened

6. **External explainer**
   - if an explainer link exists, surface it clearly as supplemental context

## Posting behavior

Do not post by default.

Draft first, then wait for the user to confirm posting.

Before posting, use the `functions.question` tool to work through the candidate
comments with the user. The purpose of this interaction is comment triage, not
workflow debugging.

Use `functions.question` only after:

- PR metadata is fetched
- local checkout is verified, or remote-only degraded mode is made explicit
- findings are stabilized
- the change walkthrough has been presented
- the rendered digest and draft posting plan are ready

Use `functions.question` to decide, for each candidate finding or comment:

- **approve as-is** — keep the comment exactly as drafted
- **refine wording** — ask the user for wording guidance or propose a tighter
  alternative, then update the draft
- **change severity / final state impact** — e.g. blocking → non-blocking,
  request changes → comment
- **convert placement** — inline ↔ top-level, or combine with another comment
- **reject/drop** — remove it from `drafts.github` and, when appropriate, mark
  the finding recommendation impact as `none`
- **hold** — keep it in the artifact but do not include it in the next posting
  plan until the user decides

### Comment triage loop

After rendering the draft plan, walk comments one at a time. For each comment,
show only:

- comment number and finding id
- target file/line or “top-level”
- severity and proposed final-state impact
- the exact proposed comment body
- a one-sentence rationale

Then call `functions.question` and ask the user to choose from: approve, refine,
severity/placement, drop, or hold. Use these exact concepts as choices. If the
user types free-form feedback, apply it directly.

Maintain a visible triage summary:

- approved comments
- comments needing edits
- dropped comments
- held comments
- resulting recommended final review state

Before posting, persist a fresh artifact reflecting the triage decisions. The
posting plan should be derived from that updated artifact, not from the original
draft or chat memory.

When the user asks to post:

- submit the full batch in one go
- include inline comments, top-level review text, and the chosen review state
- use `review-github-post` by default; it owns the batched GitHub submission
- if the user wants to drop some comments conversationally first, update the
  draft plan before posting
- if the user asks for wording changes before posting, update `drafts.github`,
  persist a new artifact with `review-artifact-write`, and post from that
  updated artifact

## Mapping artifact findings to GitHub comments

Use the artifact to decide comment placement.

### Inline comment candidates

Prefer findings where:

- `target` is `inline_candidate` or `either`
- concrete locations are present
- the issue is local enough to attach to a hunk

Use GitHub suggestion blocks when the artifact includes a small, concrete fix
that is safe to express as a replacement.

### Top-level review body

Use top-level review text for:

- cross-file concerns
- architecture or API issues
- repeated patterns
- broader approach feedback

### Review state

The artifact includes a recommendation, but you should still ask the user before
submitting a final `comment`, `approve`, or `request_changes` review.

If `drafts.github` already exists in the artifact, prefer that as the wrapper's
source of truth for rendered posting plans, while still treating the core
findings as canonical analysis data.

When posting:

- require an explicit final review state from the user
- submit the review in one batched GitHub review request when possible
- if some inline drafts lack robust location metadata, promote them into the
  top-level review body instead of failing the whole submission

## Comment style

Use the direct casual style defined by `changes-review-core`.

Prefer GitHub suggestion blocks for small concrete fixes when the artifact makes
the replacement clear and low-risk.

## Relationship to the core skill

This skill handles:

- GitHub PR acquisition
- terminal digest composition
- local checkout heuristics
- posting workflow

The underlying review method, severity model, targeting rules, performance
guidance, security/authz review, and data-exposure review come from
`changes-review-core`. This skill adds GitHub acquisition, artifact-to-comment
mapping, compact transcript output, and posting behavior.
