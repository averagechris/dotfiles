---
name: jj-vcs
description: |
  Jujutsu (jj) version control system reference. Use when working with jj repositories,
  managing bookmarks, resolving conflicts, or drafting commit messages.
---

# Jujutsu (jj) VCS Skill

Use this skill in repos with `.jj/`.

## Core Model

- The working copy is a commit.
- `@` = working copy commit.
- `@-` = parent of the working copy.
- File edits automatically amend `@`.
- There is no staging area.

## Default Workflow

1. Edit files in `@`
2. Describe with `jj describe -m "..."`
3. Finish/push with `jj ship`

Useful iteration pattern:
- `jj new` to create a fresh working copy
- `jj squash` to fold current work into the parent change

## Repo Aliases

- `jj lint` - run repo-configured checks
- `jj push` - run lints, then push
- `jj ship` - finish and push current work
- `jj sync` - fetch, then rebase onto inferred integration branch
- `jj sync --onto <revset>` - override inferred sync base

### `jj ship`
- creates a new empty working copy only if needed
- prefers the nearest non-integration bookmark
- treats `develop`, `dev`, `main`, `master`, `trunk`, and `release*` as integration bookmarks
- warns / opens a picker if bookmark or remote choice is ambiguous

### `jj sync`
- fetches first
- rebases onto:
  1. `develop` / `dev`
  2. `main` / `master` / `trunk`
  3. `release*`
  4. `trunk()` fallback

## Safety Rules

### Usually safe without asking
- `jj new`
- `jj describe` on the current working copy
- creating a new bookmark on `@`
- read-only commands like `jj diff`, `jj log`, `jj status`, `jj show`, `jj files`, `jj bookmark list`, `jj config`, `jj op log`

### Mutating commands

If the user clearly asked for the mutation, do it and rely on OpenCode's approval UI.
Only ask follow-up questions if the user's intent, target, or risk is genuinely unclear.

Common mutating commands:
- `jj squash`, `jj split`, `jj abandon`
- `jj bookmark move/delete`
- moving a bookmark to a specific rev
- `jj describe -r <rev>` on a non-working-copy revision
- `jj git push`, `jj commit`, `jj undo`, `jj resolve`

## Non-Interactive Only

Agents cannot use interactive editors or TUIs. Never use interactive jj flows.

Use non-interactive forms like:

```bash
jj describe -m "feat(scope): message"
jj split file1 file2
jj status --no-pager --color=never
jj log -n 20 --no-graph --color=never
```

Avoid:

```bash
jj describe
jj split --interactive
jj squash -i
```

Prefer `jj status` for routine checks. Use `jj show` only when you need full commit details or diffs.

## Bookmark Notes

- `main*` means bookmark `main` differs from the upstream bookmark it tracks; `*` is display notation, not part of the name.
- If a bookmark is conflicted, inspect both tips, prefer rebasing to preserve work, and only discard one side if you are sure it contains nothing unique.

Typical resolution pattern:

```bash
jj rebase -r <local-tip> -d <other-tip>
jj bookmark set main -r <new-tip>
```

## Commit Messages

Use Conventional Commits: `type(scope): short summary`

Common types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`

See the `conventional-commits` skill for details.

## Lint Integration

`jj push` can run checks before pushing.

When working in a jj repo, proactively notice whether the project already has pre-commit hooks,
CI validation steps, or standard local verification commands that should run before pushes or PRs.
If so, suggest wiring them into `jj lint` / `jj push` via `.jj-lint.toml` or repo config.

In this repo, the VCS-tracked lint config is `.jj-lint.toml`.
