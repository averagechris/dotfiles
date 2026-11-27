---
name: review-queue
description: Use when asked to check or catch up on the user's GitHub PR review queue.
---

# Review queue

Keep the team moving. Give the author concrete feedback they can act on and bring the user the choices that need their judgment.

## Refresh the queue

- Find open reviews directly requested from the intended GitHub account across repositories, including drafts. Search with `is:pr is:open user-review-requested:@me` using the correct account and host. Use the available cross-repo search and page results. Confirm per-PR state because search can lag, and report any coverage limit. Add team-only requests or mentions when the user includes them.
- Include PRs the user adds by link. Carry forward thread-local skips by host, repository, and PR number until the user revisits them. Keep a short record in the thread of each PR's reviewed revision, pending decision, and submitted reviews. Check tracked PRs directly when they drop out of search. A comment-only review can clear the request while a PR is still awaiting the author.
- On a scheduled pass, use the previous recap in the same thread when available. Reuse the review for unchanged PRs unless new checks, discussion, or other material evidence could change the verdict. Keep an empty or unchanged pass to one line.
- A queue lookup such as `just list them` reports what's pending. A request to review or catch up on the queue runs the review below. For `draft comments only` or `draft only`, keep proposed feedback in the session with zero GitHub writes, including pending reviews.

## Review and choose a verdict

- Read the PR, linked requirements, checks, and existing review threads as evidence. Pin the head and the base used for comparison. Give advisors access to the actual diff, affected callers, tests, and any material companion changes. Use an isolated checkout on the available workstation when helpful. Keep the author's code separate from the user's working copy and credentials. Run focused checks when safe, and verify consequential findings against the source. Leave code fixes and workflow reruns to the author.
- Use `advisor-council` for every reviewed PR. Collect independent reviews of the same revision and name the completed, pending, and unavailable seats. Require two independent council members to complete evidence-backed reviews before calling a routine PR ready. Use provider-eligible source access and exclude secrets and customer data. A summary-only review cannot count as code evidence.
- Recommend approval when the implementation is sound and the remaining work is small polish, an author-owned CI issue, or a routine rollout. Use evidence to distinguish an unrelated check failure from a regression or an unverified behavior. Check for coupled releases when the queue includes changes to the same version, contract, or migration. A code-ready verdict can coexist with a GitHub merge gate.
- Drafts get feedback suitable for their stage. Hold for verified material defects or missing evidence that could change the verdict. Report verdict confidence separately from merge readiness. A well-evidenced hold can have high confidence.
- Start full council scoring automatically for material reviewer disagreement, low confidence in the verdict, or a consequential assumption the available evidence leaves unresolved. Start with the full council when the need is apparent up front. Also score on request. Use [the scorecard reference](references/scorecard.md).

## Approve straightforward PRs

The owner authorizes automatic approval during review passes on their own queue, including scheduled passes. Apply all of these checks before approving.

- The PR is open, out of draft, and within this pass's scope. It introduces no new architectural concept. The recommendation is ready with at least 95% confidence in that verdict. Substantive taste or policy calls, unresolved material findings, and material reviewer dissent leave approval pending. Judge a change applying an already agreed direction against that direction. A verified unrelated CI failure or routine author-owned rollout can coexist with readiness.
- At least two independent council members reviewed the actual source for the same revision and each recommends approval. Ask routine reviewers for the five [ratings](references/scorecard.md) so they can support the decision without calling the full roster. Every completed reviewer must give at least 90 for each of the first four ratings and 95% for should merge. Wait for in-flight reviewers and record unavailable seats. If a full council was triggered, resolve the original uncertainty against the evidence before applying the gate again. Missing ratings from a completed seat leave approval pending.
- Confirm the authenticated account, PR state, reviewed head, and material base or dependency refs again immediately before approval. Skip submission if the account already has an effective approval for this head, has an unpublished human review, or the review history cannot be checked. Use a supported action that accepts the reviewed commit SHA, such as the GitHub connector's `commit_id` field. Keep the recommendation in the recap when a commit-aware action is unavailable.
- Verify the submitted approval and commit, then recheck the current head and material refs. If they moved during submission, report the approval on the old comparison and leave the new comparison pending a fresh review. Reconcile ambiguous submissions with the review history before attempting another write.

Record the approval link. Combine qualifying inline comments with the approval if the submission action supports it. Keep draft-only and lookup-only passes read-only. Approvals outside this gate need explicit direction for the reviewed revision.

## Decide what to post

- The dotfiles owner's request to review or catch up on their own queue authorizes qualifying technical comments under their intended GitHub account. Post them without asking again. A comment qualifies when the evidence and impact are concrete, the author can act on it, and the feedback fits the established tone. Give the author room to decide timing for non-blockers. Use short, relaxed, jargon-free wording. For serious technical issues, name the failure case and ask a direct question such as "If the second merge starts while the first package is still publishing, could it cancel that publish?"
- Skip cosmetic nits that add little. Keep substantive taste calls, uncertain findings, and policy or architecture choices with the user. For architecture, state what changes, what could go wrong, and the smallest workable choice. When the user has already settled a direction, check its implementation against that decision.
- Read existing threads first. Skip duplicates and settled points. Add meaningful new evidence or a concrete question to the existing discussion. Use the host's supported GitHub review tools and verify that the authenticated posting account matches the intended account, especially when discovery and posting use different tools. Immediately before posting, recheck that the PR is open, its reviewed head still matches, and the thread or inline location is current. Bind inline comments to the reviewed commit when supported and verify the returned comment or review. If the head moves, refresh the evidence before posting. If submission is ambiguous, check GitHub before retrying.
- Check for a pending review under the posting account before submitting a review. Preserve any existing user draft in full. Use a separate comment or reply that leaves the pending review untouched, or keep the feedback in the session.
- Get explicit authorization for writes outside qualifying comments and automatic approvals, including requesting changes, resolving a thread, merging, closing, or posting in Slack. Respect read-only requests and tighter host permissions.

## Recap

Before reporting a PR as ready, check that it is still open and the reviewed head and any material base or dependency refs still apply. For each PR, link the PR and any posted review or comment. Give the reviewed revision, disposition, confidence in the verdict, and the evidence or next action in one or two lines. Mark drafts, skips, changed revisions, and advisor gaps. Put decisions the user needs to make where they can find them quickly. Keep confirmed actions distinct from recommendations and pending work.
