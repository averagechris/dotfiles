---
name: suremac-jj-pr
description: Use when creating, updating, closing, watching, or sweeping GitHub PR hygiene from jj workspaces on suremac work repos. Prefer `jj pr` over bare `gh pr create`; handles jj remotes, bookmarks, sync, lints, push, CI, review polling, and open-PR follow-up reports.
---

# Suremac jj PR Workflow

Use this skill on `suremac` when the user asks to create, update, close, watch,
prepare, or sweep hygiene/follow-up for GitHub pull requests from jj workspaces,
especially for work repositories under `~/sureapp`.

## Core rule

Do **not** run bare `gh pr create` from jj workspaces. Use the repo-managed helper:

```bash
jj pr doctor
jj pr create ...
jj pr update ...
jj pr close ...
jj pr hygiene
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
     --ticket EPD-1234 \
     --title "fix(policy): concise change summary [EPD-1234]" \
     --body-file /tmp/pr-body.md
   ```

   Notes:
   - `--sync` runs `jj sync --onto <base>@<inferred-remote> --fail-on-conflicts` before checks, usually with `origin`.
   - `--run-lints` runs `jj lint`.
   - Push is enabled by default. Use `--no-push` only when explicitly needed.
   - Add `--draft` for draft PRs.
   - `--dry-run` plans auto-bookmarking without creating the bookmark.
   - Use `--remote <remote>` when the push/sync remote cannot be inferred or when `--repo owner/repo` is explicit and multiple/no matching jj remotes exist.

Auto-created bookmarks are durable. If a later sync, lint, push, or GitHub step fails, leave the bookmark in place and resume from it. Ticket values for auto-bookmarking must be simple safe identifiers using only letters, numbers, dot, underscore, or hyphen.

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

## PR hygiene sweep

When the user asks to catch up on open PRs, run PR follow-up hygiene next to the
Linear hygiene loop:

```bash
github-pr-hygiene-report
github-pr-hygiene-report --force
github-pr-hygiene-report --json
```

Prefer `github-pr-hygiene-report` for normal on-demand follow-up: it reads the
scheduled cache when it is fresh and refreshes only after the TTL expires or the
requested search, limit, TTL, workdir list, or `--no-workspaces` flag differs from the cached inputs. Use
`github-pr-hygiene-report --force` when the user explicitly wants a fresh GitHub
query now, and `github-pr-hygiene-report --json` for stable cached fields. The
shell prompt reads the same cache locally with `jq`, so prompt rendering does
not start Python or hit GitHub/jj.

The lower-level `jj pr hygiene` command searches open GitHub PRs authored by the current GitHub user
(default search: `author:@me is:pr is:open archived:false`), enriches them with
checks, review decision, unresolved comments, size, and base/head branch data,
then scans configured jj workspace roots for related local workspaces. The human
report includes links, status, review effort estimate, heuristic priority, a
suggested follow-up, and a copyable reviewer nudge for PRs that are green and
waiting for review.

Use direct `jj pr hygiene` only when you intentionally want an uncached GitHub
query from inside a jj repo. The cached wrapper exists because scheduled launchd
and shell workflows may start outside any particular jj checkout; it finds a
configured jj workdir, keeps the shared cache fresh, and avoids hitting GitHub
from prompts.

Use it before telling the user what to complain about. Prefer these outcomes:

- `needs-fix`: fix CI/review comments before asking people for more review.
- `ready`: merge or hand off the merge decision.
- `needs-review`: nudge reviewers, including the effort estimate and PR link.
- `waiting-ci`: wait or inspect CI; do not ask humans before checks are green.
- `draft`: finish or mark ready before requesting review.

Use `--search <github-search>` to narrow scope, `--limit <n>` for shorter sweeps,
and `--no-workspaces` if local workspace discovery is slow or irrelevant. The
cached wrapper also keys freshness on the TTL and configured workdir strings. Use
`--json` when another script/agent needs stable fields.

## Follow-up changes after CI/review

When CI or GitHub review feedback needs code changes, make a new jj change on top, move the PR bookmark intentionally, and push again:

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
