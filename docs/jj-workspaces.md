# jj Workspace Workflow

This documents the repo-managed `jj ws` workflow for ergonomic Jujutsu workspace management.

## Goal

`jj ws` creates, locates, forgets, and prunes Jujutsu workspaces with predictable paths and low-noise output.

The workflow should be safe and agent-friendly:

- noninteractive by default
- concise output by default
- `-q` / `--quiet` suppresses noncritical output
- destructive operations are conservative and support dry-runs or force flags
- picker flows are explicit and only used when requested

## Commands

Commands:

```bash
jj ws add <name> [-r <revset>]
jj ws list [--pick]
jj ws path <name>
jj ws path --pick
jj ws forget <name> [--force] [--keep-dir] [--no-docker] [--docker-volumes] [--dry-run]
jj ws forget --pick [options]
jj ws prune [--dry-run] [--delete] [--pick] [--yes]
jj ws root
```

`jj ws` with no arguments prints a compact usage guide.

## Quick Usage

Create and print only the path:

```bash
jj ws add feature-x -q
```

Base on the current revision:

```bash
jj ws add followup -r @
```

Enter from a shell:

```bash
cd "$(jj ws path feature-x)"
```

Preview deletion:

```bash
jj ws forget feature-x --dry-run
```

Forget and delete:

```bash
jj ws forget feature-x
```

List stale dirs:

```bash
jj ws prune
```

Agents/scripts should use `jj ws add -q`, `jj ws path <name>`, and `jj ws list`. Avoid `--pick`; it requires an interactive terminal.

## Build-Time Test Environment

The repo-managed `jj-workflow` helper runs its Rust test suite as part of the
Nix package build. Integration tests shell out to `jj`, `git`, and `npm`, create
temporary jj repositories, and push to a local bare Git remote. The package's
check phase therefore provides those tools explicitly and sets an isolated
`HOME`/`XDG_CONFIG_HOME` with test-only jj user identity so builds do not depend
on the invoking user's configuration or Nix's default `/homeless-shelter` home.

## Help and Error Ergonomics

Keep output concise and actionable:

- `jj ws` and `jj ws --help` print a compact usage guide
- `jj ws <command> --help` prints command-specific usage
- missing arguments include a usage hint
- ambiguous integration bookmarks show candidates and an example `--revision`
- multi-remote warnings mention `dotfiles.workspaces.fetch-remote`
- destructive refusals explain the required next step or flag

Do not integrate this workflow with `jj ship` in v1. Shipping often requires CI follow-up or other cleanup decisions before deleting a workspace.

## Project Groups and Directory Convention

Workspace roots are configured as project groups. Each group has:

- a project group path, such as `~/projects`
- a workspace namespace directory, defaulting to `ws`

Canonical workspace path:

```text
<project-group-path>/<workspace-dir>/<repo-name>/<workspace-name>
```

Examples:

```text
~/projects/ws/dotfiles/jj-workspaces
~/sureapp/ws/backend/auth-v2
```

If canonical parent directories do not exist, create them automatically.

The workspace namespace directory is configurable per project group. `/ws/` is the default convention.

## Host Configuration Decisions

Configure these project groups through Nix/home-manager:

- all personal hosts: `~/projects`, with workspace dir `ws`
- `suremac`: `~/projects` and `~/sureapp`, each with workspace dir `ws`

## jj Config Shape

The generated jj config uses a flat project-group list. Each item is `path:workspace-dir`; omit `:workspace-dir` to use `ws`.

```toml
[dotfiles.workspaces]
copy-envrc = "untracked"
direnv-allow = true
docker-cleanup = "auto"
docker-remove-volumes = false
picker = "fzf"
# Optional when multiple remotes exist:
# fetch-remote = "origin"
project-groups = ["~/projects:ws", "~/sureapp:ws"]
```

## Main Checkout vs Managed Workspace

A checkout is considered a managed workspace if its repo root matches the configured convention:

```text
<project-group-path>/<workspace-dir>/<repo-name>/<workspace-name>
```

Otherwise, if it is contained in a configured project group and not under that group's workspace namespace, it is treated as a main/source checkout.

This distinction controls the default base revision for `jj ws add`.

## Base Revision Selection

`jj ws add <name>` supports an explicit revision:

```bash
jj ws add feature-x -r @
jj ws add hotfix --revision main@origin
```

Explicit `-r` / `--revision` always wins.

Default behavior:

- from a managed workspace: base on `@`
- from a main checkout: fetch if safe/configured, then base on an inferred remote integration bookmark such as `main@origin`

Integration bookmark priority:

1. `develop`
2. `dev`
3. `main`
4. `master`
5. `trunk`
6. `release*`

Fetch behavior from a main checkout:

- if exactly one remote exists, fetch that remote
- if multiple remotes exist and `dotfiles.workspaces.fetch-remote` is configured, fetch that remote
- if multiple remotes exist and no fetch remote is configured, print a warning, skip fetching, and continue inference from existing remote bookmark state

If integration bookmark inference is ambiguous or impossible, fail clearly and ask the caller to specify `--revision`.

## Output and Quiet Mode

Default output should be concise. Example:

```text
created workspace billing-refactor at /home/chris/projects/ws/api/billing-refactor
base: main@origin
copied untracked .envrc
direnv allowed
```

Quiet add output still prints the workspace path, because users, shell wrappers, and agents need it:

```bash
jj ws add billing-refactor -q
```

```text
/home/chris/projects/ws/api/billing-refactor
```

For `jj ws forget -q`, print nothing on success. Errors still print.

## `.envrc` and direnv

Default behavior:

- if the source checkout has an `.envrc`
- and `.envrc` is not checked into source control
- and the destination workspace does not already have `.envrc`
- copy it to the workspace
- run `direnv allow <workspace-path>`

Tracked `.envrc` files should naturally appear in the workspace and should not be manually copied.

CLI overrides:

```bash
--no-envrc
--no-direnv
```

More elaborate setup hooks can be deferred, but the config shape should leave room for repo-configurable setup behavior later.

## Picker Support

Include picker support in v1.

Use `fzf` if available rather than implementing a Rust-native TUI initially.

Rules:

- picker runs only when explicitly requested with `--pick`
- if `fzf` is missing, fail clearly
- if not running in an interactive terminal, fail clearly
- never use picker implicitly in agent/noninteractive contexts

Picker-enabled commands:

```bash
jj ws list --pick
jj ws path --pick
jj ws forget --pick
jj ws prune --pick
```

## Listing and Path Lookup

`jj ws list` lists registered workspaces for the current repo with compact output:

```text
NAME              PATH
default           /home/chris/projects/api
billing-refactor  /home/chris/projects/ws/api/billing-refactor
auth-v2           /home/chris/projects/ws/api/auth-v2
```

No cache is planned for v1. Listing should be cheap when scoped to the current repo.

`jj ws path <name>` prints only the path, making it suitable for shell functions and agents.

## Forget Behavior

`jj ws forget <name>` should:

1. resolve the workspace name to a registered workspace path
2. refuse to forget the current workspace
3. check whether the workspace has non-empty work
4. refuse unless `--force` if non-empty work exists
5. run Docker Compose cleanup if applicable and enabled
6. run `jj workspace forget <name>`
7. delete the workspace directory unless `--keep-dir` is set
8. remove empty canonical parent directories

Supported options:

```bash
--force
--keep-dir
--no-docker
--docker-volumes
--dry-run
-q, --quiet
```

## Docker Compose Cleanup

On forget, detect Compose files in the workspace root:

```text
compose.yaml
compose.yml
docker-compose.yaml
docker-compose.yml
```

Default cleanup:

```bash
docker compose down --remove-orphans
```

With `--docker-volumes`:

```bash
docker compose down --remove-orphans --volumes
```

Do not remove volumes by default.

## Prune Behavior

`jj ws prune` cleans stale directories under:

```text
<project-group-path>/<workspace-dir>/<repo-name>/
```

A stale directory is a canonical workspace directory that is not a registered jj workspace.

Default behavior is conservative and non-destructive: print candidates only.

Deletion requires explicit intent, for example:

```bash
jj ws prune --delete
jj ws prune --pick
```

`--yes` is accepted for future confirmation flows; current deletion is gated by explicit `--delete` or picker selection.

## Workspace Name Validation

Allow workspace names matching:

```regex
^[A-Za-z0-9._-]+$
```

Reject names containing path separators, `..`, whitespace, or shell metacharacters.

## High-Level Implementation Checklist

- [x] Inspect existing `jj-workflow` helper and jj alias configuration.
- [x] Add workspace config parsing, including project groups and per-group `workspace-dir` defaulting to `ws`.
- [x] Add Nix/home-manager options for workspace project groups.
- [x] Configure `~/projects` for all personal hosts.
- [x] Configure both `~/projects` and `~/sureapp` for `suremac`.
- [x] Add `jj ws` alias wiring to the jj config.
- [x] Implement main checkout vs managed workspace detection.
- [x] Implement base revision selection and remote-fetch behavior.
- [x] Implement `jj ws root`.
- [x] Implement `jj ws list`.
- [x] Implement `jj ws path`.
- [x] Implement `jj ws add`.
- [x] Implement untracked `.envrc` copying.
- [x] Implement `direnv allow` handling.
- [x] Implement explicit `fzf` picker support for supported commands.
- [x] Implement `jj ws forget` safety checks.
- [x] Implement Docker Compose cleanup for forget.
- [x] Implement directory deletion and empty parent cleanup.
- [x] Implement `jj ws prune` with conservative default behavior.
- [x] Update repo-managed jj skills because this changes workspace workflow behavior.
- [x] Update `AGENTS.md` with the new workspace convention and agent usage guidance.
- [x] Add or update user-facing docs and keep `docs/README.md` in sync.
- [x] Run formatting and lint checks.
