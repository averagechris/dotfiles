---
name: bay-workspaces
description: >-
  Use Bay for isolated workspaces: find, clone, create, locate, and remove jj
  workspaces including repository acquisition from github.
---

# Bay workspaces

Use the returned absolute path for all work. Route edits inside a checkout to `jj-change-management`.

Bay maps repositories and their isolated Jujutsu checkouts across the device. A repository is the shared history and main checkout. A workspace is a separate working copy for one task. Use Bay first. `jj ws` exists only as a repository-local compatibility interface.

OpenCode uses Bay for its native worktree UI when the server's canonical location is a Bay-recognized Jujutsu repository. Git-only repositories keep OpenCode's built-in Git behavior.

## Find, clone, add

When the repository may not exist locally, follow this exact flow:

```bash
bay repo find <query> --json
bay repo clone <owner>/<repo> --json
bay add <repo>/<workspace> --json
```

Choose an exact slug from the find result. Check whether it is archived or already local. Ask before cloning an archived repository. Clone is safe to retry for the same repository.

Read the absolute workspace path returned by `bay add`. Use that path as `workdir` for every later shell command and as the prefix for every read, search, or edit. Do not keep working in the source checkout.

If the repository already exists, start with `bay add <repo>/<workspace> --json`. Use `bay path <repo>/<workspace>` to recover an existing workspace's absolute path.

## Base and names

From a main checkout, Bay updates safely and bases the new workspace on the inferred remote integration bookmark. From an existing managed workspace, Bay bases it on that workspace's `@`, which supports stacked work. Supply an explicit revision only when the requested base differs.

For ticket work, inspect the ticket first and name the workspace `<issue-key-lower>-<short-slug>`. Infer the repository from ticket metadata or current context. Ask only when the repository, base, or name remains ambiguous.

Do not pass routing overrides proactively. If clone reports `no_group`, ask which configured group to use. If it reports `collision`, leave the existing path untouched and offer a different basename. Never clone an archived repository without confirmation.

## Cleanup

Do not remove a workspace unless asked. Preview first:

```bash
bay rm <repo>/<workspace> --dry-run
bay rm <repo>/<workspace>
```

Bay refuses the current workspace and protects unpublished stacks. Do not force removal merely because `@` is empty; unpublished ancestors still count. Normal removal moves the directory to recoverable trash. Never add purge implicitly. Cleanup does not imply trash collection, and trash collection requires a separate explicit request.

Use `bay list --json` for bounded discovery before cleanup. Do not guess paths or delete directories directly.

## Boundaries

Bay owns repository acquisition plus workspace creation, lookup, and removal. Once inside the returned path, load `jj-change-management` for edits and local history, `jj-conflict-resolution` for conflicts, and `jj-repo-workflow` for sync, lint, publication, or handoff. `docs/bay.md` owns the operator model. `bay --help` and `docs/jj-workspaces.md` own detailed flags, hooks, compatibility, and artifact setup.
