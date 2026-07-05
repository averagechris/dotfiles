---
name: jj-repo-workflow
description: |
  Repository-level jj aliases for checks, lint onboarding, syncing, pushing,
  shipping, suremac PR creation, integration bookmark behavior, and final handoff.
---

# jj Repo Workflow

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

- Reads `.jj-lint.toml` first, then repo config `dotfiles.push-lints`.
- `.jj-lint.toml` entries may be strings or `{ name, command }` tables; omit
  `name` to use the inferred display label.
- Runs configured commands with `sh -c` from the repo root.
- Use after meaningful edits and before asking the user to review.
- If a lint fails, fix the issue and rerun the smallest relevant check first if possible.
- If no lints are configured, do not ignore it. Run:

```bash
jj lint onboard --print
```

Use onboarding output to discover project checks and pre-commit replacements. It reports high-confidence suggestions plus files to inspect: package scripts, Python pyproject/tox/nox, Makefile, justfile, Docker Compose, README/CONTRIBUTING, CI workflows, Husky/lint-staged/pre-commit/lefthook.

Agent defaults:

```bash
jj lint onboard --print        # safe human-readable discovery
jj lint onboard --json         # structured discovery
jj lint onboard --local        # set per-repo local dotfiles.push-lints
jj lint onboard --write        # write tracked .jj-lint.toml; ask first unless requested
jj lint onboard --preview --select=1,3 # preview selected .jj-lint.toml
jj lint onboard --local --select=1,3   # save only chosen numbered suggestions
jj lint onboard --write --select=2     # write only chosen suggestions to .jj-lint.toml
```

Prefer deterministic all-files commands. Avoid watch/dev/server/deploy commands and staged-file-only hooks; jj has no staging area. For Docker/Make/Just/Python workflows, inspect whether commands require services, secrets, network, mutating fix modes, or slow container builds before adding them. Prefer aggregate project commands (`scripts/check`, `make lint`, `tox run -e linting`) over duplicated primitive tool commands when onboarding suggests both.

## `jj sync`

Use for the common "update my work" workflow. It fetches from remote, infers one integration base, then runs `jj rebase -d <base>` so the current branch/stack containing `@` moves onto that base. Agents should prefer this over manually spelling out routine `jj git fetch` + `jj rebase` sequences.

Agent default:

```bash
jj sync -q --fail-on-conflicts
```

Use structured output when a script/agent needs fields:

```bash
jj sync --json --fail-on-conflicts
jj sync --json --fail-on-conflicts | jq -r '.base'
jj sync --json --fail-on-conflicts | jq -r '.conflicts[]?'
```

Base inference order:

1. `develop` / `dev`
2. `main` / `master` / `trunk`
3. `release*`
4. `trunk()` fallback

Sync prefers remote integration bookmarks like `main@origin` over local `main`. If multiple remote integration bookmarks/remotes match, it stops and asks for `--remote`, `--bookmark`, `--onto`, or per-repo jj config `dotfiles.sync.remote`.

Per-repo default remote, when useful:

```toml
# .jj/repo/config.toml
[dotfiles.sync]
remote = "origin"
```

Use `jj sync --onto <revset>` when the desired base is known.

Use explicit bases when inference may be ambiguous:

```bash
jj sync --bookmark main
jj sync --bookmark main@origin
jj sync --remote origin
jj sync --onto 'trunk()'
```

After rebase, sync checks `conflicts()`. With `--fail-on-conflicts`, conflicts produce a failing command and a clear handoff to `jj-conflict-resolution`.

## `jj push`

- Delegates to the same `jj-workflow lint` runner as `jj lint`, then pushes.
- Use when the user says push/publish but does not need the full `ship` flow.
- Skip lints only with explicit user instruction via `jj git push`.

## `jj ship`

Use when the user wants the change finished and published.

- Runs `jj lint` before moving bookmarks.
- Ships the parent of an empty working copy, not empty `@`.
- Refuses empty targets.
- Requires `--bookmark` if only integration bookmarks are nearby.
- Pushes via `jj git push` after lints pass to avoid duplicate lint runs.
- With `--tag vX.Y.Z`, creates an annotated Git tag for the exact shipped commit, pushes `refs/tags/<tag>`, and verifies the remote tag is annotated and peels to that commit. Tags are signed by default when jj GPG signing is configured; use `--no-sign` for unsigned annotated tags in automation/backfills.

## Tags

For human/agent-created release tags, prefer `jj ship --bookmark <b> --tag vX.Y.Z`. If the bookmark is already shipped, use `jj tag-push vX.Y.Z --revision <rev>`. Use `--sign` to require signing and `--no-sign` to force unsigned annotated tags. Do not use `jj tag set` for release tags that need artifacts: it creates lightweight tags, while hosts like sourcehut require annotated tags. Do not expect `jj git push --all` to create new remote tags; jj intentionally refuses that.

## `jj pr` on suremac

When creating, updating, or closing GitHub PRs for work repos from jj workspaces
on `suremac`, load/use the `suremac-jj-pr` skill and prefer `jj pr` over bare
`gh pr create`.

Typical create flow:

```bash
jj pr doctor
jj pr create --base develop --sync --run-lints --run-cr --ticket EPD-1234 --title "fix(scope): summary [EPD-1234]" --body-file /tmp/pr-body.md
jj pr watch
```

The helper infers the GitHub repo from jj remotes and always passes `gh --repo`,
so it works in non-colocated jj workspaces. Use `jj pr watch` instead of dumping
raw CI logs or full review threads into agent context; fetch details with `gh`
only when the compact summary is insufficient.

## Agent defaults

- Do not push/ship unless explicitly asked.
- Before handoff, run or suggest `jj lint` depending on task size.
- Final concise state:

```bash
jj status --no-pager --color=never
jj log -n 8 --no-pager --color=never
```

- Changelog entry is the `jj describe` message; keep it concise and Conventional-Commit style.
