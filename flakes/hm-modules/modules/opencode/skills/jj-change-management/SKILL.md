---
name: jj-change-management
description: |
  Everyday Jujutsu change work: inspect state, understand history, describe,
  split/squash, rebase, move bookmarks, and recover mistakes.
---

# jj Change Management

Use in repos with `.jj/` while editing and shaping local changes.

Load `jj-conflict-resolution` when a command creates conflicts or `jj status` reports conflicts.

## Model

- Working copy is commit `@`; parent is `@-`.
- Edits automatically amend `@`; there is no staging area.
- Prefer jj over git in colocated repos.

## Inspect: what changed and why

Use compact output first; expand only when needed.

```bash
jj status --no-pager --color=never              # current working-copy summary
jj diff --stat --no-pager --color=never         # changed files/size
jj diff --no-pager --color=never                # full patch
jj show --stat --no-pager --color=never         # current change metadata + stat
jj log-recent || jj log -n 20 --no-pager --color=never # nearby history
```

When available, prefer dotfiles aliases:

```bash
jj df --stat --no-pager --color=never       # diff from trunk(); good before review/PR
jj log-here                                 # compact @ and @-
jj log-stack                                # compact trunk()::@
jj log-ahead                                # compact trunk()..@
jj log-summary -r '<revset>' --limit 10     # compact custom revset
jj ll --no-pager --color=never              # local stack context around @
jj ld --no-pager --color=never              # descendants of @
jj la --no-pager --color=never              # ancestors of @
jj log-all --no-pager --color=never         # all revisions; use sparingly
```

## Describe: make the changelog entry

Use when the current change has a coherent purpose or before handoff.

```bash
jj describe -m "feat(scope): concise summary"
```

Use Conventional Commits. Load `conventional-commits` if uncertain.

## Shape changes

```bash
jj new                         # start separate work after finishing current @
jj squash -m "feat(scope): combined change"          # fold @ into @- with explicit message
jj squash --use-destination-message                  # fold @ into @- keeping @- message
jj split root:"path/to/file" -m "feat(scope): part"  # split files/paths into a new change
jj sync -q --fail-on-conflicts                       # common update: fetch + rebase current stack onto inferred integration base
jj rebase -d 'trunk()'                                # manual fallback: move current stack to trunk()
jj rebase -b '<rev>' -d '<dest>'                      # move branch/stack containing rev
jj rebase -s '<rev>' -d '<dest>'                      # move rev plus descendants
jj rebase -r '<rev>' -A '<after-rev>'                 # reorder/insert after another rev
jj tug                         # move nearest ancestor bookmark to @- when available
jj bookmark set <name> -r @    # create/update explicit bookmark at @
jj undo                        # undo last jj operation if it was wrong
```

Why/when:

- `jj new`: keep unrelated follow-up work separate.
- `jj squash`: combine fixups with their parent change.
- `jj split`: separate unrelated edits before describing/shipping.
- `jj sync`: preferred day-to-day update; fetches from remote, infers one integration base, then rebases the current branch/stack containing `@` onto it.
- `jj rebase`: manual parentage/order changes; do not use it to edit content.
- `jj tug`: after `jj new` or describing a stack, move the nearby feature bookmark to the completed parent.
- `jj undo`: recover from an accidental jj operation; inspect `jj op log` first if unsure.

Sync/rebase notes:

- Prefer `jj sync -q --fail-on-conflicts` for the common "update my work on top of upstream integration" workflow.
- Use plain `jj sync` when base inference is unambiguous.
- Use `jj sync --bookmark <name>`, `jj sync --bookmark <name>@<remote>`, or `jj sync --onto '<revset>'` when the desired base is known or inference may be ambiguous.
- Use `jj sync --json --fail-on-conflicts` when structured output is useful; pipe to `jq -r '.base'` or `jq -r '.conflicts[]?'` only when extracting fields.
- `jj rebase` is noninteractive but requires a destination (`-d`, `-A`, or `-B`).
- Quote revsets: `trunk()`, `conflicts()`, `@-`, and operators are shell-sensitive.
- Default selection is effectively the branch containing `@`; use explicit `-b/-s/-r` when intent matters.
- Use `-b` for a whole branch/stack, `-s` for a source plus descendants, `-r` for only selected revisions.
- After any rebase, check both status and conflicts because rebase can exit successfully while creating conflicts:

```bash
jj status --no-pager --color=never
jj log -r 'conflicts()' --no-pager --color=never
```

## Repo-level aliases

When available, prefer high-level aliases; load `jj-repo-workflow` for details.

```bash
jj lint    # run configured checks; use before handoff
jj sync    # fetch/rebase current stack onto inferred integration base
jj push    # lint then push; only when asked to push
jj ship    # lint, move/push bookmark, clean up; only when asked to ship/publish
jj ws      # managed workspaces; load jj-workspaces
```

Do not run `jj push` or `jj ship` unless the user explicitly asks to push/ship/publish.

## Noninteractive rules

Agents must avoid editors, pickers, and TUIs.

```bash
# good
jj describe -m "fix(api): handle empty response"
jj describe --stdin < message.txt
jj split root:"src/foo.rs" -m "fix(api): isolate foo fix"
jj squash -m "fix(api): combine foo fix"
jj squash --use-destination-message
jj squash root:"src/foo.rs" -m "fix(api): combine foo fix"

# bad
jj describe
jj describe --editor
jj split
jj split src/foo.rs
jj split --interactive
jj split --tool meld
jj squash
jj squash -i
jj squash --tool meld
jj squash --editor
jj ch        # fzf picker
jj prune     # fzf picker
```

Important editor traps:

- `jj describe` without `-m` or `--stdin` opens an editor.
- `jj split` without filesets opens a diff editor/TUI.
- `jj split <filesets>` without `-m` can open one or more description editors.
- Plain `jj squash` can open an editor when combining non-empty descriptions.
- Path-limited `jj squash <filesets>` can still open an editor if it empties the source change.
- Any `--interactive`, `-i`, `--tool`, or `--editor` form is not agent-safe.

Agent-safe recipes:

```bash
jj split root:"path/to/file" -m "feat(scope): selected part"
jj describe @ -m "feat(scope): remaining part"
jj squash --from <source> --into <dest> -m "feat(scope): combined change"
jj squash --from <source> --into <dest> --use-destination-message
```

Use `root:"path"` filesets or run commands from the repo root so paths resolve predictably.

## Conflicts and bookmarks

- `main*` display means bookmark differs from its tracked remote; `*` is not part of the name.
- Inspect both sides before resolving conflicted bookmarks.
- Prefer rebasing to preserve work; discard only when certain.

```bash
jj op log --limit 10 --no-pager --color=never       # recent operations/recovery points
jj bookmark list --all --no-pager --color=never     # local + remote bookmark state
jj rebase -r <local-tip> -d <other-tip>             # preserve local work on chosen base
jj bookmark set <name> -r <resolved-tip>            # point bookmark at resolved tip
```
