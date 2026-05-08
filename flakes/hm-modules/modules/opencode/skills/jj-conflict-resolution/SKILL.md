---
name: jj-conflict-resolution
description: |
  Resolve Jujutsu conflicts safely after rebase, sync, squash, or other jj
  operations. Use when jj reports conflicts or `jj log -r 'conflicts()'` is non-empty.
---

# jj Conflict Resolution

Use when `jj status`, `jj rebase`, `jj sync`, or another jj command reports conflicts.

## First inspect

```bash
jj status --no-pager --color=never
jj log -r 'conflicts()' --no-pager --color=never
jj resolve --list
jj op log --limit 10 --no-pager --color=never
```

Important: `jj rebase` can exit `0` while creating conflicts. Always inspect after rebases.

## Agent-safe resolution

Prefer direct file edits after reading the conflicted files. Then verify:

```bash
jj resolve --list
jj diff --no-pager --color=never
jj status --no-pager --color=never
```

Avoid plain `jj resolve`; it may launch an external merge tool/editor/TUI.

## If conflict is not `@`

Work on the conflicted revision explicitly:

```bash
jj new '<conflicted-rev>'
jj resolve --list
# edit files
jj squash -m "fix(scope): resolve conflict"
```

Why: resolving in a child working copy keeps the conflicted revision target clear, then squashes the resolution back.

## Noninteractive side choice

Use only when the intended side is obvious from inspection:

```bash
jj resolve --tool :ours root:path/to/file
jj resolve --tool :theirs root:path/to/file
```

For rebase conflicts, observed convention: `:ours` is the destination/current-parent side and `:theirs` is the rebased-change side. Verify conflict labels before choosing.

## Path/revset rules

- Quote revsets: `jj log -r 'conflicts()'`.
- Prefer `root:path/to/file` filesets, especially when using `jj -R /path/to/repo ...`.
- Do not use `--ignore-working-copy` or `--ignore-immutable` unless explicitly requested.

## Recovery

If resolution went wrong:

```bash
jj op log --limit 10 --no-pager --color=never
jj undo
```
