# jj workspace workflow

This documents the repo-managed `jj ws` workflow for ergonomic Jujutsu workspace management.

## Goal

`jj ws` creates, locates, forgets, and prunes Jujutsu workspaces with predictable paths and low-noise output.

The workflow should be safe and agent-friendly:

- noninteractive by default
- concise output by default
- `-q` / `--quiet` suppresses noncritical output
- destructive operations are conservative and support dry-runs or force flags
- picker flows are explicit and only used when requested

## OpenCode worktrees

When `dotfiles.opencode.bayWorktrees.enable` is enabled, OpenCode V2 uses Bay
for its worktree UI in recognized Jujutsu repositories. Registration is checked
against OpenCode's canonical location at plugin setup; Git-only locations keep
OpenCode's built-in Git strategy. Missing Bay, invalid JSON, or an unrecognized
location fails closed without replacing Git.

Creates use Bay's managed group layout rather than OpenCode's requested path.
Removes use Bay's recoverable trash behavior; unpublished work still requires
an explicit force retry, and the plugin never adds `--purge`.

## Commands

Commands:

```bash
jj ws add <name> [-r <revset>] [--venv=<copy|link|none>] [--no-envrc] [--no-venv] [--no-clone-artifacts] [--no-direnv] [--no-hooks]
jj ws list [--pick]
jj ws path <name>
jj ws path --pick
jj ws forget <name> [--force] [--purge|--keep-dir] [--no-docker] [--docker-volumes|--keep-docker-volumes] [--no-hooks] [--dry-run]
jj ws forget --pick [options]
jj ws prune [--dry-run] [--delete] [--pick] [--yes]
jj ws du
jj ws sweep [--idle <duration>] [--dry-run]
jj ws gc [--older-than <duration>] [--dry-run]
jj ws root
```

`jj ws` with no arguments prints a compact usage guide.

## Quick usage

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

Forget and move to trash:

```bash
jj ws forget feature-x
```

Delete immediately instead of trashing:

```bash
jj ws forget feature-x --purge
```

List stale dirs:

```bash
jj ws prune
```

Agents/scripts should use `jj ws add -q`, `jj ws path <name>`, and `jj ws list`. Avoid `--pick`; it requires an interactive terminal.

## Build-time test environment

The repo-managed `jj-workflow` helper runs its Rust test suite as part of the
Nix package build. Integration tests shell out to `jj`, `git`, and `npm`, create
temporary jj repositories, and push to a local bare Git remote. The package's
check phase therefore provides those tools explicitly and sets an isolated
`HOME`/`XDG_CONFIG_HOME` with test-only jj user identity so builds do not depend
on the invoking user's configuration or Nix's default `/homeless-shelter` home.

## Help and error ergonomics

Keep output concise and actionable:

- `jj ws` and `jj ws --help` print a compact usage guide
- `jj ws <command> --help` prints command-specific usage
- missing arguments include a usage hint
- ambiguous integration bookmarks show candidates and an example `--revision`
- multi-remote warnings mention `dotfiles.workspaces.fetch-remote`
- destructive refusals explain the required next step or flag

Do not integrate this workflow with `jj ship` in v1. Shipping often requires CI follow-up or other cleanup decisions before deleting a workspace.

## Project groups and directory convention

Workspace roots are configured as project groups. Each group has:

- a project group path, such as `~/projects`
- a workspace namespace directory, defaulting to `ws`
- optional GitHub repository owners used to route repositories to the group;
  owner matching is case-insensitive and `*` selects the fallback group

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

## Host configuration decisions

Configure these project groups through Nix/home-manager:

- all personal hosts: `~/projects`, with workspace dir `ws`
- `suremac`: `~/projects` (`averagechris`), `~/sureapp` (`sureapp`), and the
  `~/contrib` fallback (`*`), each with workspace dir `ws`

## Device config shape

Home Manager generates `$XDG_CONFIG_HOME/bay/config.toml` from the
`dotfiles.jujutsu.workspaces.*` options. Repository-specific hooks remain in
`.jj-workspace.toml`; device workspace settings do not belong in jj config.

```toml
schema = 1
copy-envrc = "untracked"
venv-mode = "copy"
direnv-allow = true
docker-cleanup = "auto"
docker-remove-volumes = true
picker = "fzf"
clone-artifacts = [".direnv", "target", "node_modules", ".venv"]
sweep-idle = "14d"
trash-retention = "7d"
# Optional when multiple remotes exist:
# fetch-remote = "origin"

[[groups]]
path = "~/projects"
workspaces = "ws"

[[groups]]
path = "~/sureapp"
workspaces = "ws"
```

## Main checkout vs managed workspace

A checkout is considered a managed workspace if its repo root matches the configured convention:

```text
<project-group-path>/<workspace-dir>/<repo-name>/<workspace-name>
```

Otherwise, if it is contained in a configured project group and not under that group's workspace namespace, it is treated as a main/source checkout.

This distinction controls the default base revision for `jj ws add`.

## Base revision selection

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

## Output and quiet mode

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

## `.jj-lint.toml`, `.envrc`, `.venv`, and direnv

Default behavior:

- if the source checkout has a `.jj-lint.toml` lint config
- and the destination workspace does not already have `.jj-lint.toml`
- copy it to the workspace, including when the file is ignored/untracked
- if the source checkout has an `.envrc`
- and `.envrc` is not checked into source control
- and the destination workspace does not already have `.envrc`
- copy it to the workspace
- run `direnv allow <workspace-path>`

Tracked `.jj-lint.toml` files should naturally appear in the workspace through
Jujutsu. The explicit copy exists for repos that intentionally keep local lint
configuration ignored but still want new managed workspaces to run the same
`jj lint` commands.

Tracked `.envrc` files should naturally appear in the workspace and should not be manually copied.

After the lint/`.envrc` step, `jj ws add` clones configured build artifact
directories from the source checkout into matching relative paths in the new
workspace. The configured names (`dotfiles.workspaces.clone-artifacts`,
defaulting to `[".direnv", "target", "node_modules", ".venv"]`) are matched as
directory basenames anywhere under the source checkout, including nested
monorepo paths; the walker does not descend into a directory once it has been
selected. Existing destination paths are left untouched. Cloning is strict
copy-on-write (APFS `cp -cR` on macOS, `cp -a --reflink=always` on Linux) with
no full-copy fallback: a failed item prints a warning with source and
destination, removes any partial destination, and workspace creation continues.
The walker never follows symlinks: symlinked directories are skipped entirely
(even when their basename matches a configured artifact) so cycles cannot cause
infinite recursion. Unreadable directories print a warning and are skipped.
`--no-clone-artifacts` skips every artifact, including `.venv`; an explicit
empty `clone-artifacts = []` disables cloning entirely.

If the source checkout has an untracked `.venv` with a usable `.venv/bin/python`,
`jj ws add` copies it into the workspace by default through the same artifact
clone mechanism. After copying, the helper repairs common virtualenv path
references from the source checkout to the workspace, including `pyvenv.cfg`
and text files under `.venv/bin/` such as console-script shebangs and
activation scripts. This keeps dependency updates made inside a workspace
isolated to that workspace. If the source `.venv/bin/python` is missing or
points to a missing interpreter, skip virtualenv setup rather than copying a
known-broken environment.

For scratch work where sharing the source checkout's environment is desired,
use `--venv=link`. To skip virtualenv setup entirely, use `--venv=none` or
`--no-venv`; both leave no `.venv` in the destination at all — not even an
unrepaired clone. A tracked `.venv` is never cloned or set up; it should
appear through Jujutsu like any other tracked file.

CLI overrides:

```bash
--no-envrc
--venv=<copy|link|none>
--no-venv
--no-clone-artifacts
--no-direnv
```

More elaborate setup hooks can be deferred, but the config shape should leave room for repo-configurable setup behavior later.

## Disk hygiene

`jj ws du` reports apparent bytes for each registered managed workspace as
stable TSV: `NAME`, `PATH`, `TOTAL_BYTES`, one column per configured artifact
in `dotfiles.workspaces.clone-artifacts` order, `OTHER_BYTES`, `LAST_TOUCHED`
(unix seconds), and `IDLE` (seconds). One Rust walk produces the breakdown,
total, and last-touch data; symlinks are measured as links and never followed.

`jj ws sweep [--idle <duration>] [--dry-run]` removes configured artifact
directories from managed workspaces whose last-touch time is at least the idle
threshold old. The default threshold is `dotfiles.workspaces.sweep-idle`
(default `14d`); durations are positive integers with `h`, `d`, or `w`, and
`0h` is allowed on the CLI for smoke tests. Last-touch is the newest mtime
found while recursively walking non-artifact files and directories, excluding
`.jj`; a workspace with no eligible entry uses its root mtime. Sweep never
touches the current workspace, the main checkout, or paths outside the
canonical workspace root, and it only removes directories whose basename is in
the configured artifact set. Dry-run prints exactly what normal mode would
remove, one path and apparent byte count per line.

Note: on APFS, CoW-cloned artifacts share blocks with the source checkout, so
apparent sizes can overcount real disk usage reclaimed by a sweep.

## Picker support

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

## Listing and path lookup

`jj ws list` lists registered workspaces for the current repo with compact output:

```text
NAME              PATH
default           /home/chris/projects/api
billing-refactor  /home/chris/projects/ws/api/billing-refactor
auth-v2           /home/chris/projects/ws/api/auth-v2
```

No cache is planned for v1. Listing should be cheap when scoped to the current repo.

`jj ws path <name>` prints only the path, making it suitable for shell functions and agents.

## Forget behavior

`jj ws forget <name>` should:

1. resolve the workspace name to a registered workspace path
2. refuse to forget the current workspace
3. check whether the workspace has unpublished work
4. refuse unless `--force` if any non-empty commit in the workspace stack is not reachable from remote bookmarks or remote tags
5. run `preforget` hooks from `.jj-workspace.toml` when present; otherwise run Docker Compose cleanup if applicable and enabled (see below)
6. run `jj workspace forget <name>`
7. move the workspace directory into `<workspace-root>/.trash/<unix-seconds>-<name>` unless `--keep-dir` is set; `--purge` deletes it immediately instead of trashing
8. remove empty canonical parent directories

The trash move is a same-filesystem rename. If the rename fails, the directory
stays in place and the command errors; there is no copy fallback. Trash names
get a numeric suffix at the end when a same-second removal would collide. Forgotten
workspaces stay recoverable under `.trash` until `jj ws gc` deletes them.

Supported options:

```bash
--force
--purge
--keep-dir
--no-docker
--no-hooks
--docker-volumes
--keep-docker-volumes
--dry-run
-q, --quiet
```

`--purge` and `--keep-dir` are mutually exclusive.

The published-work check intentionally looks at the whole non-empty stack ending
at the workspace's `@`, not just `@` itself. An empty `@` is only safe if its
non-empty ancestors are already reachable from remote bookmarks or remote tags.
This catches the case where an agent creates a new empty working copy after
leaving unpublished work in `@-`, while still allowing the common PR workflow
where the branch was pushed directly from the workspace's `@` commit. If
`forget` still reports unpublished work for a branch that was just merged, fetch
remote refs first so jj can see updated or deleted remote bookmarks:

```bash
jj --repository "$(jj ws path feature-x)" git fetch
jj ws forget feature-x
```

## Docker Compose cleanup

On forget, if the workspace has no `preforget` hook in `.jj-workspace.toml`, detect Compose files in the workspace root:

```text
compose.yaml
compose.yml
docker-compose.yaml
docker-compose.yml
```

Default cleanup:

```bash
docker compose down --remove-orphans --volumes
```

With `--keep-docker-volumes` or `dotfiles.workspaces.docker-remove-volumes = false`:

```bash
docker compose down --remove-orphans
```

Compose volumes are removed by default so ephemeral workspaces and smoke-test
databases do not leak after `jj ws forget --force`. Pass `--keep-docker-volumes`
when the workspace intentionally owns long-lived local data. `--docker-volumes`
is still accepted as an explicit opt-in for repos that override the config to
keep volumes by default.

## Repo lifecycle hooks (`.jj-workspace.toml`)

A repo can declare small setup and teardown steps in an optional
`.jj-workspace.toml` at its root:

```toml
version = 1

[hooks]
postcreate = ["uv sync --frozen", "pnpm install --prefer-offline"]
preforget = ["docker compose down --remove-orphans --volumes"]
```

Rules:

- only `postcreate` and `preforget` hook groups are supported; unknown keys,
  unsupported versions, empty commands, and malformed TOML are rejected before
  any hook runs
- commands run in order through `sh -c` with inherited stdio in the target
  workspace directory, with these environment variables set:
  - `JJ_WS_SOURCE`: for `postcreate`, the checkout `add` ran from; for
    `preforget`, the target workspace
  - `JJ_WS_DEST`: for `postcreate`, the new workspace; for `preforget`, the
    target workspace
  - `JJ_WS_NAME`: the workspace name
  - `JJ_WS_REPO_ROOT`: for `postcreate`, the source checkout's repo root; for
    `preforget`, the target workspace's jj root
- `postcreate` runs in the new workspace after artifact/envrc/venv setup and
  `direnv allow`; a failing command warns with the command and exit status but
  `jj ws add` still succeeds and leaves the workspace intact
- `preforget` runs during `forget` after safety checks but before
  `jj workspace forget` and before any trash/purge; a failing command names the
  command and aborts, leaving the workspace registered and on disk
- an ignored/untracked `.jj-workspace.toml` is copied into new workspaces like
  `.jj-lint.toml`; a tracked file is already materialized by jj and is never
  overwritten
- a present `preforget` array — including an empty one — replaces the builtin
  Docker Compose cleanup; when `preforget` is absent, the Docker default above
  applies

`--no-hooks` on `add` or `forget` skips repo hooks; on `forget` it also skips
the builtin Docker cleanup. `--no-docker` continues to skip only Docker.

Out of scope for now: precreate/postforget hooks, parallel hooks, a general
plugin API, Windows shells, and loading this config outside configured project
groups.

## Prune behavior

`jj ws prune` cleans stale directories under:

```text
<project-group-path>/<workspace-dir>/<repo-name>/
```

A stale directory is a canonical workspace directory that is not a registered jj workspace. The `.trash` directory itself and its contents are never candidates.

Default behavior is conservative and non-destructive: print candidates only.

Deletion requires explicit intent, for example:

```bash
jj ws prune --delete
jj ws prune --pick
```

`--delete` moves stale directories into `.trash` (recoverable until `jj ws gc` runs) rather than deleting them outright.

`--yes` is accepted for future confirmation flows; current deletion is gated by explicit `--delete` or picker selection.

## Trash collection

`jj ws gc [--older-than <duration>] [--dry-run]` deletes trash entries under the current repo's `<workspace-root>/.trash` that are at or older than the retention period. Retention comes from `dotfiles.workspaces.trash-retention` (default `7d`) or `--older-than`. Durations are positive integers with an `h`, `d`, or `w` suffix; `--older-than 0h` deletes all trash. `--dry-run` prints each path with its age without deleting anything.

A launchd/systemd timer for automatic collection is a possible follow-up; run `jj ws gc` manually or from a scheduled job for now.

## Workspace name validation

Allow workspace names matching:

```regex
^[A-Za-z0-9._-]+$
```

Reject names containing path separators, `..`, whitespace, or shell metacharacters.

## High-level implementation checklist

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
# Bay and managed Jujutsu workspaces

`bay` is the device-wide interface to managed workspaces. A group is a
configured checkout parent, a repository is its Jujutsu repository (whose main
workspace is named `default`), and a bay is any non-main workspace. Jujutsu's
workspace registry is authoritative; Bay does not reconstruct missing roots.

Use `bay list --json` from anywhere, `bay path repo/name`, `bay root repo`,
`bay add repo/topic`, and `bay rm repo/topic`. A bare name first uses the
repository containing the current directory and otherwise must be unique
device-wide. `jj ws list`, `path`, `add`, and `forget` remain compatible
repository-local spellings. Discovery is bounded to direct group children and
`<group>/<workspaces>/<repo>/<bay>/.jj`; reads use explicit `-R` and
`--ignore-working-copy` and are not cached.

Repository maintenance is also available without changing directories:
`bay prune [repo]`, `bay gc [repo]`, `bay du [repo]`, and `bay sweep [repo]`.
They accept the same operation flags as their `jj ws` counterparts. The
repository may be selected by configured basename or path; when omitted, Bay
uses the repository containing the current directory. It never applies a
maintenance command across every configured repository.

## Onboard a GitHub repository with Bay

Use this three-command flow when the repository is not on the device yet:

```bash
# 1. Search without changing the filesystem.
bay repo find insurance --json

# 2. Choose a repos[].slug, then clone its main checkout.
bay repo clone SureApp/insurance-api --json

# 3. Create the workspace where the work will happen.
bay add insurance-api/lin-123-renewal-fix --json
```

`bay repo find` accepts a search term, an `OWNER/REPO` slug, or a GitHub clone or
browser URL. Search can be narrowed with `--owner LOGIN` and `--limit N`. Before
cloning, inspect the selected result's `archived` and `local` fields:

- `local: null` means Bay did not find the routed checkout.
- `local.status: "present"` means the path has a remote for that GitHub repo.
- `local.status: "foreign"` means the expected path exists but identifies a
  different repo. Do not overwrite or remove it.
- If `archived` is `true`, ask the user to confirm before cloning. Clone itself
  only prints a warning; it does not require confirmation.

Do not proactively pass `--group` or `--as`. Bay routes by the repository owner:

1. `--group PATH`, when explicitly requested, selects that configured group.
2. Otherwise, the first case-insensitive exact owner in `githubOwners` wins.
3. Otherwise, the first group whose `githubOwners` contains `"*"` wins.
4. Without a match, clone exits with `no_group`. Ask the user which configured
   group to use rather than choosing one.

On `suremac`, the wildcard routes unmatched owners to `~/contrib`. It does not
mean that every repository goes there; exact `averagechris` and `sureapp`
routes take precedence.

Bay chooses HTTPS for a public repository when the viewer has only read or
triage access, or no reported permission. It chooses SSH for private repos and
repos where the viewer has higher access. Use `--protocol ssh|https` only when
the user needs to override that rule.

Clone is idempotent when the destination is already a Git or Jujutsu checkout
with a remote identifying the same GitHub repo. Its result then has
`status: "exists"`; otherwise a new clone has `status: "cloned"`. A nonempty
non-repository path or a checkout for another repo returns `collision` and does
not modify the path. Only after that collision should you offer a different
basename with `--as NAME`. Bay never renames, removes, or cleans up an existing
path automatically.

### JSON contract and errors

`bay repo find ... --json` writes this shape to stdout:

```json
{
  "schema": 1,
  "query": "insurance",
  "repos": [{
    "slug": "SureApp/insurance-api",
    "owner": "SureApp",
    "name": "insurance-api",
    "description": "Insurance API",
    "url": "https://github.com/SureApp/insurance-api",
    "archived": false,
    "private": true,
    "updated_at": "2026-01-02T03:04:05Z",
    "group": "/Users/chris/sureapp",
    "local": null
  }]
}
```

`bay repo clone ... --json` writes `{"schema":1,"repo":{...}}`. The `repo`
object contains `slug`, `owner`, `name`, `url`, `clone_url`, `protocol`, `group`,
`path`, `status`, `default_branch`, `archived`, and `private`. `bay add --json`
uses the workspace command's schema and returns the created workspace record;
pass its reported path to subsequent tools.

JSON failures go to stderr as
`{"schema":1,"error":{"code":"...","message":"...","candidates":[],"details":...}}`.
Exit status 2 with `code: "usage"` means invalid input. Exit status 3 uses
`not_found`, `no_group`, or `collision`; collision details include `path` and
`existing_remotes`. Operational failures exit 1 with `gh_unavailable`,
`gh_auth`, `gh_failed`, or `clone_failed`.
