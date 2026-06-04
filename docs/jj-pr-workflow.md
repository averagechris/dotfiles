# jj PR Workflow

`jj pr` is an opt-in Jujutsu alias backed by the repo-managed `jj-workflow`
Rust helper. It is intended for `suremac` work repositories that use GitHub and
jj workspaces, including non-colocated workspaces where `gh pr create` cannot
discover a `.git` directory.

The helper keeps the workflow jj-native while delegating GitHub operations to the
GitHub CLI with an explicit repository:

```bash
gh pr create --repo owner/repo ...
```

This avoids the common failure mode where bare `gh pr create` exits with
`fatal: not a git repository` inside jj-only workspaces.

## Enablement

The workflow is disabled by default and exposed through the Home Manager option:

```nix
dotfiles.jujutsu.prWorkflow.enable = true;
```

`suremac` enables it. Other hosts do not get the `jj pr` alias unless they opt
in.

The module also writes default jj config used by auto-bookmarking:

```toml
[dotfiles.pr]
auto-bookmark = true
bookmark-template = "{whoami}/{ticket-number}/{short-description}"
```

Per-repo jj config can override these values.

## Commands

### Doctor

Inspect inferred repo, base, head bookmark, existing PR state, blockers, and
warnings:

```bash
jj pr doctor
jj pr doctor --json
```

The JSON output is versioned and intended for agents/scripts.

`doctor` is informational: it reports blockers in output but exits
successfully so humans can use it as a diagnostic command. Scripts and agents
should inspect the JSON `blockers` array before proceeding.

### Create

Create a PR with explicit body input:

```bash
jj pr create \
  --base develop \
  --sync \
  --run-lints \
  --run-cr \
  --ticket EPD-1234 \
  --title "fix(policy): concise summary [EPD-1234]" \
  --body-file /tmp/pr-body.md
```

Behavior:

1. Infers the GitHub repository from `jj git remote list`, preferring `origin`.
2. Infers the PR base from remote integration bookmarks unless `--base` is
   provided.
3. Requires the create head bookmark to point at `@`, unless `--head` is passed
   explicitly. This avoids accidentally creating a PR from an ancestor bookmark
   and omitting the current work.
4. If no head bookmark is found and auto-bookmarking is enabled, creates one
   from `dotfiles.pr.bookmark-template`; this requires `--ticket`.
5. Runs `jj sync --onto <base>@<inferred-remote> --fail-on-conflicts` when
   `--sync` is passed. This is usually `origin`, but follows the inferred or
   explicit `--remote` when available.
6. Runs `jj lint` when `--run-lints` is passed.
7. Runs `cr review` when `--run-cr` is passed and stops on nonzero exit.
8. Pushes the head bookmark by default.
9. Fails loudly if an open PR already exists for the head bookmark.
10. Creates the PR using `gh pr create --repo owner/repo ...`.

`create` only blocks on conflicts that are relevant to the PR stack, so
unrelated conflicted changes elsewhere in the jj repo are reported by
`doctor` as warnings rather than preventing an otherwise clean PR. Before it
creates an auto-bookmark or pushes, `create` also checks that the current change
has a description and points to `jj describe -m ...` when it does not.

Useful flags:

```bash
--draft       # create a draft PR
--no-push     # skip the default push
--dry-run     # print intended create command without mutating state; auto-bookmarking is planned but not created
--repo owner/repo
--remote remote-name
--head bookmark
--short-description slug
```

When `--repo owner/repo` is explicit, `jj pr create` tries to find a jj Git
remote whose GitHub URL matches that repo before pushing. If none or multiple
matching remotes are found, pass `--remote <remote>` or use `--no-push` and push
manually.

If base inference falls back to the jj revset `trunk()`, `jj pr` fails and asks
for `--base <branch>` because `trunk()` is not a valid GitHub PR base branch.

Auto-created bookmarks are durable: once `jj pr create` creates the local
bookmark, it leaves that bookmark in place even if a later sync, lint,
CodeRabbit, push, or GitHub step fails. This makes failed runs easy to resume.
Ticket values used in the bookmark template must contain only letters, numbers,
dot, underscore, or hyphen.

### Update

Update only explicitly requested fields on the open PR for the inferred head
bookmark:

```bash
jj pr update --title "fix(policy): updated title [EPD-1234]"
jj pr update --body-file /tmp/pr-body.md
jj pr update --base main
```

`update` accepts a jj-style base such as `main@origin`, but sends only the
bookmark name (`main`) to GitHub.

Use `--pr <number>` when inference is ambiguous.

### Close

Close the GitHub PR only. Local jj changes, bookmarks, and remote branches are
left untouched:

```bash
jj pr close
jj pr close --pr 1234
```

## Agent workflow

OpenCode on `suremac` includes the `suremac-jj-pr` skill. Agents should load/use
that workflow for work PR creation and should not call bare `gh pr create` from
jj workspaces.

When CI or review feedback requires follow-up work, create a new jj change on
top, move the PR bookmark intentionally, and push again:

```bash
jj new @
# edit files
jj describe -m "fix(scope): address PR feedback"
jj bookmark set <pr-bookmark> -r @
jj git push --bookmark <pr-bookmark>
```

`jj pr` intentionally does not force/update remote bookmarks automatically. If a
push fails due to divergence, resolve the bookmark state manually before
retrying.

### Watch

Wait for GitHub checks and unresolved review threads with compact output:

```bash
jj pr watch
jj pr watch --interval 60s --timeout 30m
jj pr watch --once
jj pr watch --json
```

Defaults are a 60-second poll interval and a 30-minute timeout. `watch` treats
an empty check list as pending so newly-created PRs do not look green before CI
attaches checks. It exits 0 only when all checks are passing and no unresolved
review comments or blocking review decisions remain. It exits nonzero
immediately when a check fails/cancels, `CHANGES_REQUESTED` is reported, or
unresolved review comments are present, printing a compact one-screen summary:
check counts, failing check names with links, pending check names, review
decision, and unresolved review comments grouped as first-line excerpts with
permalinks.

If the selected PR is already closed or merged, `watch` prints that state
explicitly and exits nonzero instead of presenting stale checks as active work.

Useful flags:

```bash
--ignore-comments  # only gate on checks
--required         # pass --required to gh pr checks
--once             # print one status snapshot and do not poll; exits nonzero if pending
--json             # machine-readable snapshot; polling mode emits newline-delimited JSON
```

For detailed logs or full comment bodies, use the printed links or query GitHub
directly with `gh`; `jj pr watch` intentionally keeps output small to avoid
blowing up agent context windows.
