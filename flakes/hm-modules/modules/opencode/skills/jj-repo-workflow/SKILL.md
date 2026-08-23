---
name: jj-repo-workflow
description: "Use when running repo-level jj workflow aliases: `jj lint` and lint onboarding, `jj sync`, `jj push`, `jj ship`, release tags via `jj tag-push`, `jj pr` on suremac, integration bookmark inference, and pre-handoff checks. Do not use for low-level change shaping (load `jj-change-management`) or workspace management (load `jj-workspaces`)."
---

# jj repo workflow

Use when preparing, updating, validating, pushing, or shipping a change.

## Commands: when and why

```bash
jj lint                 # run repo-configured checks; use before handoff/push
jj sync -q --fail-on-conflicts # fetch + rebase current stack onto inferred integration base
jj sync --json --fail-on-conflicts # structured agent/script output
jj sync --onto <revset> # sync to explicit base when inference is wrong
jj push                 # run lints, then push current bookmark/change; only when asked
jj ship --bookmark <b>  # finish/publish selected work; only when asked to ship/publish
jj ship --bookmark <b> --tag vX.Y.Z # ship and publish a human/agent-created tag
jj tag-push vX.Y.Z --revision <rev> # publish a tag after the bookmark is already shipped
jj pr doctor            # suremac-only GitHub PR helper preflight for jj workspaces
jj pr watch             # compact GitHub check/review polling for an existing PR
```

## `jj lint`

- Reads `.jj-lint.toml` first, then repo config `dotfiles.push-lints`. Entries may be strings or `{ name, command }` tables; omit `name` to use the inferred label.
- Runs configured commands with `sh -c` from the repo root. Use after meaningful edits and before asking for review.
- On failure, fix the issue and rerun the smallest relevant check first if possible.
- With no lints configured, do not ignore it:

```bash
jj lint onboard --print
```

Onboarding output reports high-confidence suggestions plus files to inspect: package scripts, Python pyproject/tox/nox, Makefile, justfile, Docker Compose, README/CONTRIBUTING, CI workflows, Husky/lint-staged/pre-commit/lefthook.

```bash
jj lint onboard --print                 # safe human-readable discovery
jj lint onboard --json                  # structured discovery
jj lint onboard --local                 # set per-repo local dotfiles.push-lints
jj lint onboard --write                 # write tracked .jj-lint.toml; ask first unless requested
jj lint onboard --preview --select=1,3  # preview selected .jj-lint.toml suggestions
jj lint onboard --local --select=1,3    # save only chosen numbered suggestions
jj lint onboard --write --select=2      # write only chosen suggestions
```

Prefer deterministic all-files commands. Avoid watch/dev/server/deploy commands and staged-file-only hooks; jj has no staging area. For Docker/Make/Just/Python workflows, check whether commands need services, secrets, network, mutating fix modes, or slow container builds before adding them. Prefer aggregate project commands (`scripts/check`, `make lint`, `tox run -e linting`) over duplicated primitive tool commands.

## `jj sync`

Fetches from remote, infers one integration base, then rebases the branch/stack containing `@` onto it. Agents should prefer this over hand-spelled `jj git fetch` + `jj rebase`.

Base inference order: `develop`/`dev`, then `main`/`master`/`trunk`, then `release*`, then `trunk()` fallback. Remote integration bookmarks like `main@origin` win over local `main`. If multiple remote candidates match, sync stops and asks for `--remote`, `--bookmark`, `--onto`, or per-repo config:

```toml
# .jj/repo/config.toml
[dotfiles.sync]
remote = "origin"
```

After rebase, sync checks `conflicts()`. With `--fail-on-conflicts`, conflicts fail the command and hand off to `jj-conflict-resolution`.

## `jj push`

Delegates to the same lint runner as `jj lint`, then pushes. Use when the user says push/publish but does not need the full `ship` flow. Skip lints only with explicit user instruction via `jj git push`.

## `jj ship`

Runs lints, then ships the parent of an empty working copy (never empty `@`), refusing empty targets and requiring `--bookmark` if only integration bookmarks are nearby. Pushes via `jj git push` after lints pass to avoid duplicate lint runs.

With `--tag vX.Y.Z`, creates an annotated Git tag for the exact shipped commit, pushes `refs/tags/<tag>`, and verifies the remote tag is annotated and peels to that commit. Tags are signed by default when jj GPG signing is configured; `--no-sign` forces unsigned annotated tags in automation/backfills, `--sign` requires signing.

## Tags

Prefer `jj ship --bookmark <b> --tag vX.Y.Z`; if the bookmark is already shipped, use `jj tag-push vX.Y.Z --revision <rev>`. Do not use `jj tag set` for release tags that need artifacts: it creates lightweight tags, while hosts like sourcehut require annotated tags. Do not expect `jj git push --all` to create new remote tags; jj intentionally refuses that.

## `jj pr` on suremac

When creating, updating, or closing GitHub PRs for work repos from jj workspaces on `suremac`, load the `suremac-jj-pr` skill and prefer `jj pr` over bare `gh pr create`.

```bash
jj pr doctor
jj pr create --base develop --sync --run-lints --ticket EPD-1234 --title "fix(scope): summary [EPD-1234]" --body-file /tmp/pr-body.md
jj pr watch
```

The helper infers the GitHub repo from jj remotes and always passes `gh --repo`, so it works in non-colocated jj workspaces. Use `jj pr watch` instead of dumping raw CI logs or full review threads into agent context; fetch details with `gh` only when the compact summary is insufficient.

## Agent defaults

- Do not push/ship unless explicitly asked.
- Before handoff, run or suggest `jj lint` depending on task size.
- Final concise state:

```bash
jj status --no-pager --color=never
jj log-recent || jj log -n 8 --no-pager --color=never
```

- The changelog entry is the `jj describe` message; keep it concise and Conventional-Commit style.
