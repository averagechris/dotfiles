---
name: jj-change-management
description: >-
  Use for local jj change work: status, diff, describe, new, split, squash,
  manual rebase, bookmarks, and undo. Route conflicts to
  `jj-conflict-resolution`, repository lifecycle to `jj-repo-workflow`, and
  repository acquisition or isolated checkouts to `bay-workspaces`.
---

# jj change management

Use this skill to inspect and shape changes in the current checkout. The working copy is commit `@`, its parent is `@-`, and edits amend `@` without staging.

## Inspect and describe

Start small, then expand only when needed.

```bash
jj status --no-pager --color=never
jj diff --stat --no-pager --color=never
jj diff --no-pager --color=never
jj log -n 12 --no-pager --color=never
jj describe -m "feat(scope): concise summary"
```

Load `conventional-commits` when the description type, scope, or breaking-change marker is unclear.

## Shape local changes

```bash
jj new
jj split root:"path/to/file" -m "feat(scope): selected part"
jj squash --use-destination-message
jj squash --from <source> --into <dest> -m "fix(scope): combined change"
jj rebase -b '<rev>' -d '<dest>'
jj bookmark set <name> -r @
```

Use `new` to separate follow-up work, `split` to separate unrelated edits, and `squash` to combine a fix with its target. Use manual `rebase` only when you intend to change local parentage or order. Quote revsets and use `root:"path"` filesets from the repository root.

Every command must stay noninteractive. Pass `-m` or `--stdin` to commands that may open an editor. Give `split` an explicit fileset. Do not use editor, tool, picker, or interactive flags.

## Bookmarks and recovery

```bash
jj bookmark list --all --no-pager --color=never
jj op log --limit 10 --no-pager --color=never
jj undo
```

Inspect the operation log before undoing uncertain work. Inspect both bookmark targets before resolving a divergent bookmark. Prefer rebase plus an explicit `bookmark set`; discard a target only when its work is known to be redundant.

## Boundaries

- If status or a command reports conflicts, load `jj-conflict-resolution`.
- For lint, onboarding, sync, push, ship, release tags, or handoff, load `jj-repo-workflow`.
- For finding or cloning repositories and creating, locating, or removing isolated checkouts, load `bay-workspaces`.
- Never publish unless the user explicitly asks. This skill does not own push or ship.
