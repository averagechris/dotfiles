---
name: suremac-jj-pr
description: Use on suremac to create, update, close, watch, comment on, request review for, or sweep GitHub PRs from jj workspaces. Prefer `jj pr` over bare `gh pr create`. Covers PR identity, publication consent, reviewer communication, CI, and follow-up.
---

# Suremac jj PR workflow

Use this skill only on `suremac` for GitHub PR work, especially in work repositories under `~/sureapp`. Use `jj-change-management` for local change shaping, `jj-conflict-resolution` for conflicts, `jj-repo-workflow` for lint, sync, push, and ship, and `bay-workspaces` for repository acquisition or isolated checkouts. Detailed helper flags and output schemas belong in `jj pr --help` and `docs/jj-pr-workflow.md`.

## Core rule

Prefer the repository's `jj pr` helper. Do not use bare `gh pr create` from a jj workspace. The helper resolves the GitHub repository from jj remotes and passes an explicit repository identity to GitHub.

Before any create, update, close, watch, or comment operation, confirm the intended repository, base, PR, head bookmark, and current change. Never guess when multiple remotes, bookmarks, or PRs are plausible. `jj pr create` must publish the current work, not an ancestor selected merely because it already has a bookmark.

## Publication boundary

Creating a PR or pushing its bookmark publishes work. Do it only when the user explicitly asks to create, push, ship, publish, or perform an equivalent action. Preparing a title or body, checking readiness, or asking for review does not authorize publication. Updating or closing an existing PR also requires a clear request for that mutation.

Run the repository's required sync and lint gates before publication. If sync creates conflicts, stop and load `jj-conflict-resolution`. Do not force-push through bookmark divergence or silently switch the PR's head, base, or repository. Ask when resolving the mismatch could overwrite or detach work.

## Create and update

For a new PR:

1. Inspect helper diagnostics and the jj stack.
2. Confirm a suitable bookmark points at the intended PR tip. Create one deliberately if needed.
3. Confirm repository, base, title, body, draft state, and reviewers.
4. Sync and run configured checks through the owning workflow.
5. Create through `jj pr`, then read back the resulting PR identity and key fields.
6. Watch CI and review state when the request includes follow-up.

An automatically created bookmark is durable. If a later check, push, or GitHub operation fails, resume from it rather than making a second identity. If an open PR already exists for the head bookmark, update that PR or ask what to do. Never create a duplicate.

For an existing PR, resolve it from the confirmed bookmark or explicit PR identity. Update only the fields the user requested. Closing a PR closes the GitHub PR; it must not delete local changes or bookmarks. Verify the final state after any mutation.

## PR body policy

Write for a reviewer deciding whether the change is safe to merge. Keep the body concise and explain:

1. the problem and its effect;
2. the chosen solution and non-obvious reasoning;
3. the result, scope limits, and rollout risk when relevant;
4. verification outcomes and anything material that was not tested.

Link the Linear issue once with context. Do not repeat the title, narrate the diff, dump commands or logs, or describe agent and workspace logistics. Quantify claims when evidence exists. Put long evidence in a comment or linked artifact. For user-visible or risky behavior, include the smallest useful before-and-after evidence and use the relevant Suremise skill for its mechanics.

## Comments, replies, and reviewers

When commenting on Chris's behalf, begin with:

```markdown
`<model name> <model version> commenting on behalf of chris`
```

For a reply to a person, use `responding` instead of `commenting`. Use the actual model and version. Keep comments direct, answer first, and keep one concern per comment. Use a GitHub suggestion block for a small concrete edit. Disagree with a reason and evidence; when accepting feedback, say what will change and where. Reply in the existing thread and preserve explicit repository identity.

Resolve requested colleagues through the helper's reviewer mapping. If a name is missing or ambiguous, investigate once and confirm ambiguity with the user before storing or using an identity. Do not tag a guessed GitHub account.

## Watch and hygiene

Use `jj pr watch` for compact CI, review-decision, and unresolved-thread status. Follow links into detailed logs or comments only when needed. A closed or merged PR is terminal, not a stale CI failure. Do not ignore unresolved comments unless the user explicitly asks for a CI-only gate.

For an open-PR hygiene request, use the suremac hygiene report before making recommendations. Process outcomes in this order:

- Fix failing CI and review comments before requesting more review.
- Wait for pending CI before nudging reviewers.
- Finish drafts before requesting review.
- For green PRs awaiting review, provide the PR link and a concise reviewer nudge.
- Treat merge-ready PRs as a merge or handoff decision, not permission to merge.

Use cached normal reporting unless the user asks for a fresh query. Cache internals, report flags, and field definitions live in the helper documentation.

## Follow-up after CI or review

Make feedback fixes in a new jj change on top of the reviewed tip. Describe the change, run the configured lint gate, then move the existing PR bookmark to the new tip intentionally. Push only with publication authorization. Re-check CI and unresolved review threads afterward.

Never raw-push first and lint later. Never move a similarly named bookmark without confirming it is the PR head. If feedback reveals a conflict, repository mismatch, or divergent remote bookmark, stop and hand off to the owning skill rather than improvising destructive recovery.
