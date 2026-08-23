---
name: jj-conflict-resolution
description: Use when jj reports conflicts after rebase, sync, squash, or another operation, when `jj status` or `jj log -r 'conflicts()'` lists conflicted revisions, or when resolving conflicted files. Do not use for routine change shaping; load `jj-change-management`.
---

# jj conflict resolution

`jj rebase` can exit 0 while creating conflicts. Inspect after every rebase.

## Inspect first

```bash
jj status --no-pager --color=never
jj log -r 'conflicts()' --no-pager --color=never
jj resolve --list
jj op log --limit 10 --no-pager --color=never
```

## Resolve agent-safe

Prefer direct edits to the conflicted files, then verify:

```bash
jj resolve --list
jj diff --no-pager --color=never
jj status --no-pager --color=never
```

Avoid plain `jj resolve`; it may launch an external merge tool/editor/TUI.

If the conflict is not in `@`, work on the conflicted revision explicitly:

```bash
jj new '<conflicted-rev>'
jj resolve --list
# edit files
jj squash -m "fix(scope): resolve conflict"
```

Resolving in a child working copy keeps the conflicted revision target clear; squashing moves the resolution back.

## Noninteractive side choice

Use only when inspection makes the intended side obvious:

```bash
jj resolve --tool :ours root:path/to/file
jj resolve --tool :theirs root:path/to/file
```

For rebase conflicts, observed convention: `:ours` is the destination/current-parent side and `:theirs` is the rebased-change side. Verify conflict labels before choosing.

## Path/revset rules

- Quote revsets: `jj log -r 'conflicts()'`.
- Prefer `root:path/to/file` filesets, especially with `jj -R /path/to/repo ...`.
- Never use `--ignore-working-copy` or `--ignore-immutable` unless explicitly requested.

## Recovery

If a resolution went wrong:

```bash
jj op log --limit 10 --no-pager --color=never
jj undo
```
