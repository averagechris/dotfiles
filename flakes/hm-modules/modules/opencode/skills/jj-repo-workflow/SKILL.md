---
name: jj-repo-workflow
description: Use for repository-level jj workflow: lint and onboarding, sync, push, ship, annotated release tags, and final handoff. Never publish without an explicit request. Route local shaping, conflicts, Bay workspace lifecycle, and suremac GitHub PRs to their owning skills.
---

# jj repository workflow

Use this skill to validate, update, publish, or hand off a coherent change. Load `jj-change-management` for local split, squash, describe, rebase, or bookmark work.

## Validate

Run repository-configured checks after meaningful edits and before handoff:

```bash
jj lint
```

If no lints are configured, inspect safe suggestions with `jj lint onboard --print`. Adding local or tracked lint configuration changes repository behavior, so ask before writing it unless the user requested onboarding. Prefer deterministic all-files checks. Reject watch servers, deploy commands, mutating fix modes, and staging-only hooks.

## Sync

```bash
jj sync -q --fail-on-conflicts
```

Sync fetches, infers one integration base, and rebases the stack containing `@`. Use an explicit base only when inference is ambiguous or wrong. If sync reports conflicts, stop and load `jj-conflict-resolution`. Do not continue toward publication with unresolved conflicts.

## Publish

Do not run push, ship, or tag publication unless the user explicitly asks to publish.

```bash
jj push
jj ship --bookmark <bookmark>
jj ship --bookmark <bookmark> --tag vX.Y.Z
jj tag-push vX.Y.Z --revision <rev>
```

`push` validates and pushes the current work. `ship` validates, selects the intended nonempty change, moves the bookmark, and publishes it. Prefer `ship --tag` when shipping a release. Use `tag-push` only when the bookmark is already shipped.

Release tags must be annotated. Do not substitute lightweight tag creation, and do not assume an all-refs push creates a remote release tag. Let configured signing policy apply unless the user requests a supported override.

## GitHub pull requests on suremac

Creating, updating, reviewing, watching, or closing a GitHub PR belongs to `suremac-jj-pr`. Load that skill and follow its `jj pr` workflow. This skill owns validation and publication boundaries, not PR mechanics.

## Handoff

Before handoff:

1. Run the smallest relevant checks, then `jj lint` when configured.
2. Confirm status and inspect the final diff.
3. Confirm `conflicts()` is empty after any sync or rebase.
4. Report checks, skipped checks, current change state, and whether anything was published.

Repository acquisition and isolated checkout lifecycle belong to `bay-workspaces`.
