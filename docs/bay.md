# Bay

Bay is the device-wide interface for repositories and isolated Jujutsu workspaces. Use it when you need to find or clone a repository, create a task checkout, locate one, or remove it safely.

`jj ws` is the repository-local compatibility interface to the same workspace engine. It is useful when you are already inside a repository and need implementation-specific controls. See [Repository-local workspace engine](/docs/jj-workspaces.md) for configuration, hooks, environment cloning, base inference details, and compatibility behavior.

Complete command syntax belongs in `bay --help` and each subcommand's help.

## Mental model

Bay organizes checkouts at three levels:

- A group is a configured parent directory such as `~/projects`, `~/sureapp`, or `~/contrib`.
- A repository is the main checkout and shared Jujutsu history. Its Jujutsu workspace is named `default`.
- A bay is a non-main workspace for one task.

Jujutsu's workspace registry is authoritative. Bay does not reconstruct a missing repository root from loose directories.

The standard layout is:

```text
<group>/<repository>
<group>/<workspaces>/<repository>/<bay>
```

With the default `workspaces = "ws"`, a repository and task workspace might be:

```text
~/projects/dotfiles
~/projects/ws/dotfiles/update-opencode
```

Different groups may use different workspace directory names. Home Manager writes the device configuration to `$XDG_CONFIG_HOME/bay/config.toml`.

## Which command to use

| Need | Command | Scope |
| --- | --- | --- |
| Search GitHub | `bay repo find <query> --json` | Device-wide |
| Clone a main checkout | `bay repo clone <owner>/<repo> --json` | Device-wide |
| Create a task workspace | `bay add <repo>/<name> --json` | Device-wide |
| List repositories and workspaces | `bay list --json` | Device-wide |
| Print a workspace path | `bay path <repo>/<name>` | Device-wide |
| Print a repository's workspace root | `bay root <repo>` | Device-wide |
| Remove a task workspace | `bay rm <repo>/<name>` | Device-wide |
| Inspect one repository's workspaces | `jj ws list` | Current repository |
| Use setup or removal overrides | `jj ws add`, `jj ws forget` | Current repository |
| Maintain workspace storage | `bay prune`, `bay gc`, `bay du`, `bay sweep` | Selected repository |

A selector with `repo/name` is unambiguous. A bare workspace name first uses the repository containing the current directory. Outside a repository, the name must be unique across configured groups.

Maintenance never runs across every configured repository. Give Bay a repository selector, or run it from a checkout that identifies one.

## Find, clone, add

When a repository is not on the device, use this sequence:

```bash
bay repo find insurance --json
bay repo clone SureApp/insurance-api --json
bay add insurance-api/lin-123-renewal-fix --json
```

`bay repo find` accepts search text, an `OWNER/REPO` slug, a GitHub browser URL, or a clone URL. You can narrow a search with `--owner` and `--limit`. Before cloning, check the selected result:

- `archived: true` means the repository is archived. Confirm before cloning it.
- `local: null` means Bay found no checkout at the routed path.
- `local.status: "present"` means that path has a remote for the same GitHub repository.
- `local.status: "foreign"` means the expected path identifies another repository. Do not overwrite or remove it.

Bay routes clones by GitHub owner. An explicit `--group` wins. Otherwise, the first case-insensitive owner match wins, then the first group configured with the `"*"` fallback. If no group matches, Bay returns `no_group`; ask which configured group to use.

On `suremac`, exact routes place `averagechris` and `sureapp` repositories in their configured groups. The wildcard sends unmatched owners to `~/contrib`.

Do not pass `--group` or `--as` preemptively. Use `--as` only after Bay reports a destination collision and the user chooses a different local basename. Bay never renames or deletes the existing path.

Bay chooses HTTPS for public repositories when GitHub reports read-only, triage, or no viewer permission. It chooses SSH for private repositories and repositories with higher access. `--protocol` overrides that choice.

Clone is idempotent when the destination already identifies the same GitHub repository. It reports `exists` instead of cloning again. A nonempty non-repository path or a checkout for another repository reports `collision` without changing the path.

For scripts and agents, read the absolute path from the JSON result of `bay add` and use it for every later command and file operation.

## Output and failures

Use `--json` for discovery, clone, creation, and list operations when another
tool will consume the result. Successful JSON records include `schema: 1`.
Failures write a structured error to stderr and return a nonzero status.

The error code tells you what to do next:

- `usage` means the command or selector is invalid. Check the subcommand help.
- `not_found` means no configured repository or workspace matched.
- `no_group` means owner routing found no destination group. Ask for a group.
- `collision` means the destination exists but is not the requested repository.
- `gh_unavailable`, `gh_auth`, and `gh_failed` identify GitHub CLI failures.
- `clone_failed` means the underlying clone did not complete.

Human-readable output is intentionally concise. Do not parse it when JSON is
available.

## Creating a workspace

From a main checkout, Bay fetches when remote selection is safe and bases the new workspace on the inferred remote integration bookmark. From an existing managed workspace, it bases the new workspace on that workspace's `@`. This makes stacked work the default when you create a bay from another bay.

Pass `-r` only when the requested base differs from those defaults.

Workspace names accept letters, numbers, `.`, `_`, and `-`. Bay rejects path separators, whitespace, `..`, and shell metacharacters.

Creation may copy local lint and environment files, clone configured build artifacts with copy-on-write, run `direnv allow`, and run repository `postcreate` hooks. These behaviors come from device and repository configuration, not from Bay-specific agent instructions. See [the shared engine reference](/docs/jj-workspaces.md) when you need to change or diagnose them.

## OpenCode integration

When `dotfiles.opencode.bayWorktrees.enable` is enabled, OpenCode uses Bay for its worktree UI only when the server's canonical location is a Bay-recognized Jujutsu repository.

Git-only repositories keep OpenCode's built-in Git behavior. Missing Bay, invalid Bay JSON, or an unrecognized location fails closed and leaves the Git strategy in place.

OpenCode creation uses Bay's group layout rather than OpenCode's requested path. Removal uses recoverable trash. If Bay refuses unpublished work, OpenCode may offer an explicit force retry, but the integration never adds `--purge`.

## Removing and cleaning up

Preview removal when the target or its cleanup behavior is uncertain:

```bash
bay rm repo/topic --dry-run
bay rm repo/topic
```

Bay refuses to remove the current workspace. It also checks the whole non-empty stack ending at the workspace's `@` for commits that remote bookmarks or tags cannot reach. An empty `@` does not make unpublished ancestors safe to remove.

Normal removal forgets the Jujutsu workspace and moves its directory to the repository's `.trash` directory with a same-filesystem rename. It does not purge files. Trash remains recoverable until a separate garbage-collection command deletes it.

Use `--force` only after checking work Bay reports as unpublished. Do not add `--purge` unless the user explicitly wants immediate deletion. A failed trash move leaves the directory in place and returns an error.

The maintenance commands have separate jobs:

- `bay prune [repo]` finds canonical workspace directories that are no longer registered. Its default is a report. `--delete` moves them to trash.
- `bay gc [repo]` permanently deletes trash entries old enough to meet the retention setting. Use `--dry-run` first when the deletion was not already requested.
- `bay du [repo]` reports apparent workspace and artifact sizes.
- `bay sweep [repo]` removes configured build artifact directories from idle workspaces. It skips the current workspace, main checkout, and paths outside the canonical root.

On APFS, copy-on-write artifacts share blocks with the source checkout, so apparent sizes can overstate the disk space that `sweep` will reclaim.

Never delete managed workspace directories by hand. Use Bay so Jujutsu registration, unpublished-work checks, repository hooks, Docker cleanup, and trash behavior stay in sync.

## Lifecycle and environment

A bay is disposable as a checkout, but its commits may not be disposable. The Jujutsu repository stores history shared by all workspaces. The workspace directory holds that bay's materialized files, ignored artifacts, and local environment state.

Creation starts with a selected revision, materializes the checkout, prepares configured local files and artifacts, then runs setup hooks. Removal runs safety checks and teardown hooks before it forgets the workspace and trashes the directory.

This split explains two common surprises:

- Removing a workspace does not remove published commits from repository history.
- An empty working-copy commit can still sit on top of unpublished ancestors, so Bay may refuse removal.

Repository-specific setup belongs in `.jj-workspace.toml`. Device defaults belong in Bay's generated configuration. Keep detailed flag and hook behavior in [docs/jj-workspaces.md](/docs/jj-workspaces.md), not in OpenCode skill bodies.
