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
jj ws forget <name>              # forget and move to .trash when safe
jj ws prune --dry-run            # find stale workspace dirs
jj ws du                         # per-workspace apparent size breakdown (TSV)
jj ws sweep --dry-run            # preview artifact cleanup for idle workspaces
jj ws sweep                      # remove artifact dirs from idle workspaces
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
- Disk hygiene: `jj ws du` shows apparent bytes per workspace (artifact columns + other). `jj ws sweep [--idle 14d]` removes only configured artifact directories from workspaces idle past the threshold; it never touches the current workspace, the main checkout, or source files. APFS CoW means reported sizes can overcount real usage.

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
- Untracked `.venv` is copied by default when `.venv/bin/python` is usable: the copy is a strict CoW clone (APFS/reflink, no full-copy fallback), then common virtualenv path references are repaired so dependency updates stay isolated to the workspace. Broken source virtualenvs are skipped instead of copied.
- Build artifact directories (`dotfiles.workspaces.clone-artifacts`, default `.direnv`, `target`, `node_modules`, `.venv`) are CoW-cloned from the source checkout into matching relative paths, including nested monorepo paths. Existing destinations are untouched; failures warn and continue.
- `--venv=link` shares the source checkout's `.venv`; `--no-venv` / `--venv=none` skip virtualenv setup; `--no-clone-artifacts` skips all artifact cloning including `.venv`.
- `--no-envrc` or `--no-direnv` skips copying/allowing the local environment.
- `--no-hooks` skips `.jj-workspace.toml` hooks (on `forget` it also skips the default Docker cleanup).

## Repo lifecycle hooks

Repos can declare setup/teardown steps in an optional `.jj-workspace.toml` at the repo root:

```toml
version = 1

[hooks]
postcreate = ["uv sync --frozen", "pnpm install --prefer-offline"]
preforget = ["docker compose down --remove-orphans --volumes"]
```

- Unknown keys, unsupported versions, empty commands, and malformed TOML are rejected before any hook runs.
- Commands run in order via `sh -c` with inherited stdio in the target workspace, with `JJ_WS_SOURCE`, `JJ_WS_DEST`, `JJ_WS_NAME`, and `JJ_WS_REPO_ROOT` set.
- `postcreate` runs after workspace creation; a failure warns but leaves the workspace intact.
- `preforget` runs during `forget` after safety checks; a failure aborts before forgetting or trashing.
- An ignored/untracked `.jj-workspace.toml` is copied into new workspaces like `.jj-lint.toml`; a tracked one is already materialized and never overwritten.
- A present `preforget` array (even empty) replaces the builtin Docker Compose cleanup; when absent, the Docker default applies.

## Cleanup safety

```bash
jj ws list
jj ws forget <name> --dry-run
jj ws forget <name> --force
jj ws prune --dry-run
jj ws gc --dry-run
```

- `forget` refuses the current workspace and refuses unpublished work unless forced with `--force`.
- After `jj workspace forget`, the directory is moved into `<workspace-root>/.trash/<unix-seconds>-<name>` (same-filesystem rename; collision suffixes are appended at the end), so untracked files stay recoverable. `--purge` deletes immediately; `--keep-dir` leaves the directory in place.
- `jj ws gc [--older-than <duration>] [--dry-run]` deletes trash older than the retention period (`dotfiles.workspaces.trash-retention`, default `7d`; `0h` deletes all).
- `prune --delete` moves stale dirs into `.trash`; `.trash` itself never appears in prune or pickers.
- Safety checks the whole non-empty stack ending at the workspace's `@`, not just `@`: an empty `@` is safe only when its non-empty ancestors are already reachable from remote bookmarks or remote tags. This avoids false positives after agents push a PR directly from the working-copy commit while still catching unpublished work left in `@-`.
- If a just-merged workspace still looks unpublished, run `jj --repository "$(jj ws path <name>)" git fetch` and retry before using `--force`.
- When Compose files are detected and the repo has no `preforget` hook, `forget` runs Docker Compose cleanup and removes Compose volumes by default so smoke-test databases/queues do not leak after deletion. Use `--keep-docker-volumes` to preserve local Compose data intentionally; `--docker-volumes` remains an explicit opt-in for repos that override the default config.
