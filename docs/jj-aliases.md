# jj aliases

This repository installs a small set of global Jujutsu aliases through the Home
Manager `jujutsu` module. The aliases are meant to keep day-to-day and
agent-driven inspection commands short, noninteractive, and low-noise.

## Compact log aliases

Agent history showed repeated hand-written commands like:

```bash
jj log -r 'trunk()::' --limit 10 \
  --no-graph --no-pager --color=never \
  -T 'change_id.short() ++ " " ++ description.first_line() ++ "\n"'
```

Use these aliases instead:

```bash
jj log-summary -r 'trunk()::' --limit 10
jj log-recent
jj log-here
jj log-stack
jj log-ahead
```

They render one compact line per change with:

- current-working-copy marker (`@`) when applicable
- short change ID
- short commit ID
- `(empty)` marker when applicable
- bookmarks and tags when present
- description first line, or `(no description set)`

### `jj log-summary`

Generic compact `jj log` wrapper. It accepts normal `jj log` arguments:

```bash
jj log-summary -r 'trunk()::' --limit 10
jj log-summary -r 'main | main@origin | @'
jj log-summary -r 'parents(@) | @'
```

Use this when the revset is task-specific and you only want to avoid repeating
the template and output flags.

### `jj log-recent`

Shows the 10 most recent changes with the compact template:

```bash
jj log-recent
```

### `jj log-here`

Shows the working copy and its parent:

```bash
jj log-here
```

This replaces the common orientation pattern of `jj status` plus a templated
`jj log -r '@ | @-'` when a compact identity check is enough.

### `jj log-stack`

Shows the ancestry path from `trunk()` through `@`:

```bash
jj log-stack
```

Use this to inspect the current stack with trunk context included.

### `jj log-ahead`

Shows changes from `trunk()` to `@`, excluding trunk itself:

```bash
jj log-ahead
```

Use this when you only need the local stack entries that are ahead of trunk.

## Existing workflow aliases

The same module also installs higher-level helpers documented elsewhere when
`dotfiles.jujutsu.workflowAliases.enable` is true, which is the default:

- [`jj ws`](/docs/bay-workspaces.md) for managed workspaces
- [`jj pr`](/docs/jj-pr-workflow.md) on hosts that enable the GitHub PR helper
- [`jj ship` and `jj tag-push`](/docs/jj-tag-workflow.md) for publishing and
  annotated release tags

Minimal servers that only need basic `jj` commands can disable those helper
aliases to avoid retaining the `jj-workflow` runtime closure:

```nix
dotfiles.jujutsu.workflowAliases.enable = false;
```
