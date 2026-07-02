---
name: jj-workspaces
description: |
  Managed jj workspace workflow: create isolated checkouts, work on tickets or
  Linear issues, resolve workspace paths, and safely clean up workspaces.
---

# jj Workspaces

Use when work should happen in a separate checkout instead of the current repo directory.

Managed paths are:

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

- From a main checkout: fetches when safe, then bases on inferred remote integration bookmark.
- From another managed workspace: bases on `@`, useful for stacked/branch-off work.
- Use `-r @` to explicitly branch from current work.
- Use `-r <integration>@origin` or similar when the desired base is known.

## Agent rules

- Never use `--pick`; it is interactive.
- Prefer `-q` for `add`.
- Run future shell commands with `workdir=<workspace-path>`.
- Use absolute paths under `<workspace-path>` for file reads/edits/searches.
- Do not keep editing the source checkout after creating a workspace.
- Do not cleanup unless asked; preview with `--dry-run` first.

## Ticket/Linear flow

When asked to work on an issue:

1. Load/use Linear tooling to inspect the issue.
2. Infer repo from issue metadata, project/team conventions, or the current repo.
3. Name workspace `<issue-key-lower>-<slug-title>`.
4. In the inferred repo:

```bash
jj ws add <workspace-name> -q
```

5. Report the path and work from that path.

Ask only if repo or workspace name cannot be inferred safely.

## Environment behavior

- `.jj-lint.toml` is copied from the source checkout when it is absent in the new workspace, including ignored/untracked local lint configs.
- Untracked `.envrc` is copied by default and `direnv allow` runs by default.
- Untracked `.venv` is copied by default when `.venv/bin/python` is usable, with APFS/reflink clone attempts first and common virtualenv path references repaired so dependency updates stay isolated to the workspace. Broken source virtualenvs are skipped instead of copied.
- Use `--venv=link` to share the source checkout's `.venv`, or `--no-venv` / `--venv=none` to skip virtualenv setup.
- Use `--no-envrc` or `--no-direnv` if copying/allowing local environment is undesirable.

## Cleanup safety

```bash
jj ws list
jj ws forget <name> --dry-run
jj ws forget <name> --force
jj ws prune --dry-run
```

`forget` refuses the current workspace and refuses unpublished work unless forced. Safety checks the whole non-empty stack ending at the workspace's `@`, not just `@` itself: an empty `@` is safe only when its non-empty ancestors are already reachable from remote bookmarks or remote tags. This avoids false positives after agents push a PR directly from the working-copy commit while still catching unpublished work left in `@-`. If a just-merged workspace still looks unpublished, run `jj --repository "$(jj ws path <name>)" git fetch` and retry before using `--force`. It runs Docker Compose cleanup when compose files are detected and removes Compose volumes by default so smoke-test databases/queues do not leak after workspace deletion. Use `--keep-docker-volumes` when you intentionally want to preserve local Compose data; `--docker-volumes` remains available as an explicit opt-in for repos that override the default config.
