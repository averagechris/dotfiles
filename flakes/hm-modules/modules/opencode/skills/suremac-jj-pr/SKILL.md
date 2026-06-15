---
name: suremac-jj-pr
description: Use when creating, updating, closing, or watching GitHub PRs from jj workspaces on suremac work repos. Prefer `jj pr` over bare `gh pr create`; handles jj remotes, bookmarks, sync, lints, CodeRabbit, push, CI, and review polling.
---

# Suremac jj PR Workflow

Use this skill on `suremac` when the user asks to create, update, close, watch, or prepare a GitHub pull request from a jj workspace, especially for work repositories under `~/sureapp`.

## Core rule

Do **not** run bare `gh pr create` from jj workspaces. Use the repo-managed helper:

```bash
jj pr doctor
jj pr create ...
jj pr update ...
jj pr close ...
```

The helper infers the GitHub repository from `jj git remote list` and always calls GitHub CLI commands with explicit `--repo owner/repo`, which works in non-colocated jj workspaces where `gh pr create` cannot discover `.git`.

## Standard create flow

1. Inspect current state:

   ```bash
   jj pr doctor
   ```

   Use JSON for scripts or when you need stable fields:

   ```bash
   jj pr doctor --json
   ```

2. Ensure there is a suitable jj bookmark at `@`. `jj pr create` intentionally
   does not infer an ancestor bookmark for creation because that can omit the
   current work. If none exists, pass a ticket so `jj pr create` can auto-create
   one from the configured template:

   ```text
   {whoami}/{ticket-number}/{short-description}
   ```

3. Create the PR with explicit body input:

   ```bash
   jj pr create \
     --base develop \
     --sync \
     --run-lints \
     --run-cr \
     --ticket EPD-1234 \
     --title "fix(policy): concise change summary [EPD-1234]" \
     --body-file /tmp/pr-body.md
   ```

   Notes:
   - `--sync` runs `jj sync --onto <base>@<inferred-remote> --fail-on-conflicts` before checks, usually with `origin`.
   - `--run-lints` runs `jj lint`.
   - `--run-cr` runs `cr review --base <remote>/<branch>` and stops on a
     nonzero exit. The CodeRabbit base is derived from the same jj base used for
     sync/PR creation, converting jj remote bookmarks like `main@origin` to Git
     refs like `origin/main` so stale local `main` bookmarks do not balloon the
     diff.
   - Push is enabled by default. Use `--no-push` only when explicitly needed.
   - Add `--draft` for draft PRs.
   - `--dry-run` plans auto-bookmarking without creating the bookmark.
   - Use `--remote <remote>` when the push/sync remote cannot be inferred or when `--repo owner/repo` is explicit and multiple/no matching jj remotes exist.

Auto-created bookmarks are durable. If a later sync, lint, CodeRabbit, push, or GitHub step fails, leave the bookmark in place and resume from it. Ticket values for auto-bookmarking must be simple safe identifiers using only letters, numbers, dot, underscore, or hyphen.

Before creating a PR, the helper checks the PR-relevant stack for conflicts and
requires the current change to have a jj description. If it reports an empty
description, run `jj describe -m "<conventional commit message>"` before
retrying.

## Existing PRs

`jj pr create` fails loudly if an open PR already exists for the head bookmark. Do not create duplicates.

Update only requested fields:

```bash
jj pr update --title "fix(policy): updated title [EPD-1234]"
jj pr update --body-file /tmp/pr-body.md
jj pr update --base main
```

Close the GitHub PR only; local jj bookmarks and changes are left untouched:

```bash
jj pr close
```

## CI and review watch

Use `jj pr watch` instead of dumping raw CI logs or full review threads into the
agent context:

```bash
jj pr watch
jj pr watch --interval 60s --timeout 30m
jj pr watch --once --json
```

The helper polls GitHub checks, unresolved review threads, and review decisions.
It prints a compact summary with check counts, failing checks plus links,
pending checks, review decision, and first lines/permalinks for unresolved review
comments. It treats empty check lists as pending, exits 0 only when checks pass
and no unresolved comments/blocking review decisions remain, and exits nonzero
when checks fail, `CHANGES_REQUESTED` is present, comments need attention, or
`--once` observes a pending state. With `--json` in polling mode it emits
newline-delimited JSON snapshots.

If the PR is already closed or merged, `jj pr watch` reports that state directly
and exits nonzero; do not treat stale check output from closed PRs as active work.

Use the printed links or `gh` directly only when detailed logs/full comments are
needed. Prefer `--ignore-comments` only when the user explicitly wants to gate on
CI checks alone.

## Follow-up changes after CI/review

When CI or CodeRabbit/GitHub review feedback needs code changes, make a new jj change on top, move the PR bookmark intentionally, and push again:

```bash
jj new @
# edit files
jj describe -m "fix(scope): address PR feedback"
jj bookmark set <pr-bookmark> -r @
jj git push --bookmark <pr-bookmark>
```

Then re-check the PR with GitHub/CircleCI tools as appropriate.

## Failure handling

- If `jj pr create` reports an existing PR, use `jj pr update` or ask the user whether to close/update it.
- If push fails due to remote bookmark divergence, do not force-push automatically. Read the helper hints and ask if destructive/update semantics are needed.
- If sync reports conflicts, load `jj-conflict-resolution` and resolve before continuing.
- If CodeRabbit exits nonzero, inspect and address the review before retrying PR
  creation. If running CodeRabbit manually for the same PR, pass the same
  explicit base (for example `cr review --base origin/main`) instead of relying
  on CodeRabbit's default local base selection.
