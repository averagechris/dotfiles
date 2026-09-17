---
name: jj-conflict-resolution
description: Use only when jj reports conflicts or `conflicts()` is nonempty. Resolve by direct edits or an explicit side, stay noninteractive, verify no conflicts remain, then return to the skill that handed off.
---

# jj conflict resolution

Use this skill only for an existing conflict. A rebase can exit successfully while leaving conflicts.

## Inspect

```bash
jj status --no-pager --color=never
jj log -r 'conflicts()' --no-pager --color=never
jj resolve --list
```

Read the conflicted files and surrounding diff. Prefer direct edits. Avoid plain `jj resolve`, which may launch a merge tool.

If inspection proves one side is correct, select it explicitly and verify the result:

```bash
jj resolve --tool :ours root:path/to/file
jj resolve --tool :theirs root:path/to/file
```

For rebase conflicts, confirm the displayed labels before choosing a side. Do not infer side meaning from a remembered convention. Quote revsets and use root-relative filesets.

If the conflict is outside `@`, create a child at the conflicted revision, edit there, and squash the resolution back with an explicit message. Keep every command noninteractive. Never pass editor or interactive flags.

## Verify

```bash
jj diff --no-pager --color=never
jj status --no-pager --color=never
jj log -r 'conflicts()' --no-pager --color=never
```

Do not return until `conflicts()` is empty and the resolved diff preserves both intended behaviors.

If the resolution is wrong, inspect `jj op log`, then use `jj undo`. Return to `jj-change-management` for local shaping, `jj-repo-workflow` for sync or handoff, or `bay-workspaces` for isolated checkout lifecycle.
