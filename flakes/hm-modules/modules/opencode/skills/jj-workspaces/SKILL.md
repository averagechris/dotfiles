---
name: jj-workspaces
description: Use when creating or working in an isolated jj workspace checkout, stacking work off current changes, mapping a Linear issue or ticket to a workspace, resolving `jj ws` paths, or cleaning up stale workspaces. Do not use for everyday change shaping in the current checkout; load `jj-change-management`.
---

# jj workspaces

Use when work should happen in a separate checkout instead of the current repo directory.

Managed path layout:

```text
<project-group>/<workspace-dir>/<repo>/<workspace>
```

## Commands: when and why

```bash
jj ws add <name> -q              # create workspace; prints path only enough for agents
jj ws add <name> -r <revset> -q  # create from explicit base/current change
jj ws path <name>                # resolve path for existing workspace
jj ws list                       # inspect registered workspaces
jj ws forget <name> --dry-run    # preview cleanup/deletion
jj ws forget <name>              # forget/delete when safe
jj ws prune --dry-run            # find stale workspace dirs
```

Capture `jj ws add -q` output and treat it as the repo root for subsequent tools.

## Base selection

- From a main checkout: fetches when safe, then bases on the inferred remote integration bookmark.
- From another managed workspace: bases on `@`, useful for stacked/branch-off work.
- `-r @` explicitly branches from current work; `-r <integration>@origin` when the desired base is known.

## Agent rules

- Never use `--pick`; it is interactive.
- Prefer `-q` for `add`.
- Run future shell commands with `workdir=<workspace-path>`.
- Use absolute paths under `<workspace-path>` for file reads/edits/searches.
- Do not keep editing the source checkout after creating a workspace.
- Do not clean up unless asked; preview with `--dry-run` first.

## Ticket/Linear flow

When asked to work on an issue:

1. Load/use Linear tooling to inspect the issue.
2. Infer repo from issue metadata, project/team conventions, or the current repo.
3. Name the workspace `<issue-key-lower>-<slug-title>`.
4. In the inferred repo:

```bash
jj ws add <workspace-name> -q
```

5. Report the path and work from that path.

Ask only if repo or workspace name cannot be inferred safely.

## Environment behavior

- `.jj-lint.toml` is copied from the source checkout when absent in the new workspace, including ignored/untracked local lint configs.
- Untracked `.envrc` is copied by default and `direnv allow` runs by default.
- Untracked `.venv` is copied by default when `.venv/bin/python` is usable: APFS/reflink clone attempts first, then common virtualenv path references are repaired so dependency updates stay isolated to the workspace. Broken source virtualenvs are skipped instead of copied.
- `--venv=link` shares the source checkout's `.venv`; `--no-venv` / `--venv=none` skip virtualenv setup.
- `--no-envrc` or `--no-direnv` skips copying/allowing the local environment.

## Cleanup safety

```bash
jj ws list
jj ws forget <name> --dry-run
jj ws forget <name> --force
jj ws prune --dry-run
```

- `forget` refuses the current workspace and refuses unpublished work unless forced with `--force`.
- Safety checks the whole non-empty stack ending at the workspace's `@`, not just `@`: an empty `@` is safe only when its non-empty ancestors are already reachable from remote bookmarks or remote tags. This avoids false positives after agents push a PR directly from the working-copy commit while still catching unpublished work left in `@-`.
- If a just-merged workspace still looks unpublished, run `jj --repository "$(jj ws path <name>)" git fetch` and retry before using `--force`.
- When Compose files are detected, `forget` runs Docker Compose cleanup and removes Compose volumes by default so smoke-test databases/queues do not leak after deletion. Use `--keep-docker-volumes` to preserve local Compose data intentionally; `--docker-volumes` remains an explicit opt-in for repos that override the default config.
