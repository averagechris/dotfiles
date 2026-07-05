---
name: jj-vcs
description: |
  Router for Jujutsu (jj) skills. Load this in jj repositories when you are
  unsure which focused jj skill applies.
---

# jj Skill Router

Use focused skills instead of keeping all jj guidance in context.

- `jj-change-management`: while editing/shaping changes; status, diff, log, describe, split/squash, rebase, bookmarks.
- `jj-conflict-resolution`: when jj reports conflicts; inspect conflicts, resolve safely, avoid merge-tool traps.
- `jj-repo-workflow`: when validating/updating/publishing; `jj lint`, `jj sync`, `jj push`, `jj ship`, `jj tag-push`.
- `jj-workspaces`: when isolating work in another checkout; `jj ws add/path/list/forget`, Linear/ticket workspaces.

Default to CLI use. Prefer noninteractive, compact output:

```bash
jj status --no-pager --color=never
jj diff --stat --no-pager --color=never
jj log-recent || jj log -n 20 --no-pager --color=never
```

Never use interactive `jj` flows from an agent.
