---
name: jj-repo-workflow
description: |
  Repository-level jj aliases for checks, lint onboarding, syncing, pushing,
  shipping, integration bookmark behavior, and final handoff.
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
```

## `jj lint`

- Reads `.jj-lint.toml` first, then repo config `dotfiles.push-lints`.
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

- Runs lints, then pushes.
- Use when the user says push/publish but does not need the full `ship` flow.
- Skip lints only with explicit user instruction via `jj git push`.

## `jj ship`

Use when the user wants the change finished and published.

- Runs `jj lint` before moving bookmarks.
- Ships the parent of an empty working copy, not empty `@`.
- Refuses empty targets.
- Requires `--bookmark` if only integration bookmarks are nearby.
- Pushes via `jj git push` after lints pass to avoid duplicate lint runs.

## Agent defaults

- Do not push/ship unless explicitly asked.
- Before handoff, run or suggest `jj lint` depending on task size.
- Final concise state:

```bash
jj status --no-pager --color=never
jj log -n 8 --no-pager --color=never
```

- Changelog entry is the `jj describe` message; keep it concise and Conventional-Commit style.
