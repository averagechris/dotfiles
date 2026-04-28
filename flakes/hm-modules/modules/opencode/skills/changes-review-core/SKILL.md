---
name: changes-review-core
description: Reusable review workflow for GitHub PRs, local diffs, and patch-based code review with direct, high-signal feedback.
---

# Changes Review Core

Use this skill for reviewing code changes regardless of where the diff came
from. This is the shared review methodology for:

- GitHub pull requests
- local/self-review of unmerged changes
- patch or email-based review flows

This skill is intentionally source-agnostic. It focuses on **how to review** and
**how to structure findings**, not on how to fetch GitHub metadata, post
comments, or render a source-specific UI.

## Design choices

- Keep the review methodology reusable across change sources.
- Separate review analysis from source-specific fetch/post mechanics.
- Default to a recommendation of **comment** unless stronger evidence exists.
- Use a concise, direct, casual tone with no praise padding.
- Treat data exposure in responses and logs as a first-class review category.
- Emit a structured review artifact instead of source-specific comments.

## Primary review goals

Review changes against both the stated intent and the broader system impact.

### 1. Intent alignment

- Does the implementation match the stated goal from the PR, issue, ticket, or
  patch description?
- Does the code solve the right problem?
- Is there a simpler or safer approach?

### 2. System and API implications

- Does this approach create bad long-term commitments?
- Does it lock the system into an awkward API or data shape?
- Does it push complexity into the wrong layer?
- Are there rollout, migration, compatibility, or ownership risks?

### 3. Security and authorization

- Are authentication and authorization checks correct and complete?
- Are permission boundaries enforced at the correct layer?
- Could callers access actions or data they should not access?
- Are trust boundaries explicit and safe?

### 4. Data exposure

- What data is exposed in API responses?
- What data is exposed in logs, traces, or metrics?
- Is sensitive or internal-only data leaking unnecessarily?
- Are debugging fields, identifiers, or internal state being surfaced in ways
  that create risk?

### 5. Code quality and repo standards

- Does the code follow modern standards and the repository's own patterns?
- Are abstractions, naming, and structure consistent with the rest of the code?
- Is the implementation maintainable?

### 6. Performance

Prioritize performance review in this order:

1. data access patterns and queries
2. query count and query shape
3. avoidable scans or repeated work
4. allocation and iteration overhead in meaningful paths

Look for:

- N+1 queries
- inefficient joins or filters
- repeated fetching of the same data
- unnecessary full-collection passes
- extra allocations or copies in hot or high-volume paths

## Review process

1. Understand the stated intent from the available context.
2. Examine the actual changed code and identify hotspots.
3. Compare implementation against intent.
4. Evaluate broader system, API, security, data exposure, and performance
   implications.
5. Classify findings by severity and comment target.
6. Draft review output in a form that can later be adapted to the source system
   (GitHub comments, email review notes, local summary, etc.).

## Severity model

Use these buckets:

- **blocking**
  - correctness, security, authorization, API, or performance problems that are
    meaningfully risky
- **non-blocking**
  - important improvements or concerns that should be discussed but do not
    automatically justify requesting changes
- **nit**
  - small correctness, style, naming, consistency, or cleanup issues

Do **not** automatically choose a final review disposition. Recommend whether
the review *leans* toward `comment`, `approve`, or `request_changes`, but the
final disposition remains a user decision.

## Structured review artifact

Write the final output as a structured review artifact using the
`review-artifact-write` tool.

The artifact should be platform-neutral and strict enough for wrappers to adapt
to GitHub comments, email review, or local/self-review summaries.

### Required top-level fields

- `version`: use `1`
- `source`:
  - `kind`: one of `github_pr`, `local_diff`, `patch_review`, `other`
  - `title`
  - optional source metadata such as URL, repository, base ref, and head ref
  - for GitHub PRs, include `owner`, `repo`, `prNumber`, `baseSha`, and
    `headSha` when available
  - include `worktreeRoot` when local files are available and location-based
    excerpt rendering should work deterministically
  - include `workingDirectory` when relevant to how the review was run
- `intentSummary`
- `overallAssessment`
- `recommendedDisposition`: one of `comment`, `approve`, `request_changes`
- `findings`: array of structured findings

### Required finding fields

- `id`
- `severity`: `blocking`, `non_blocking`, `nit`
- `scope`: `local`, `cross_file`, `architectural`
- `concernArea`: one of
  - `intent`
  - `architecture`
  - `api`
  - `security`
  - `authz`
  - `data_exposure`
  - `performance`
  - `code_quality`
- `target`: `inline_candidate`, `summary_candidate`, or `either`
- `summary`
- `rationale`
- `recommendationImpact`: `none`, `comment`, `approve`, `request_changes`
- `locations`: zero or more precise location objects when the finding maps to
  concrete files or lines

### Optional finding fields

- `suggestedChange`: concise remediation guidance
- `concreteReplacement`: exact replacement text for a small concrete fix

### Location model

Each location should include:

- `file`
- optional `startLine`
- optional `endLine`
- optional `symbol`
- optional `diffSide`
- optional `diffLine`

Use locations whenever a finding can be tied to a concrete place in the diff or
codebase.

## Tone guidance

Default tone:

- concise
- direct
- casual
- no flattery
- no unnecessary softening

Good examples:

- `do x here`
- `y would be better if z`
- `this should enforce authz at the service layer`
- `this response includes data we probably should not expose`

Avoid padded praise or vague framing.

## Selected excerpt guidance

Keep the artifact itself structured and compact. Do not stuff repeated code or
large diff excerpts into it.

If a tiny excerpt is necessary for clarity, keep it short and only include it as
part of a wrapper's presentation layer, not as the primary representation of the
finding.

## Wrapper draft sections

Source-specific wrappers may add a `drafts` section to the artifact.

For GitHub, this can include:

- drafted inline comments
- drafted top-level summary bullets
- a draft full review body
- a recommended GitHub review state

These wrapper drafts should be derived from the core findings rather than
replacing them.

## Use with source-specific wrappers

This skill should be paired with source-specific wrappers when needed.

Examples:

- GitHub PR wrapper: fetch PR metadata, changed files, and posting actions
- local diff wrapper: gather `jj diff` or equivalent
- patch/email wrapper: parse the patch description and changed hunks

The wrapper is responsible for acquisition, source-specific presentation, and
publication. This skill is responsible for analysis and structured review
artifact output.
