# jj Tag Workflow

Human/agent-created release tags are opt-in. Repos whose CI/CD creates tags do
not need this workflow.

## Ship and tag together

```bash
jj ship --bookmark main --tag v0.2.1
```

`jj ship --tag` tags the exact commit that `jj ship` published, creates an
annotated Git tag in jj's underlying Git store, pushes `refs/tags/<tag>` to the
selected remote, and verifies that the remote tag is annotated and peels to the
shipped commit.

Tags are signed by default when jj GPG signing is configured, for example when
`signing.backend = "gpg"` and `signing.behavior = "own"`. Use `--no-sign` for
an unsigned annotated tag in automation or backfill contexts:

```bash
jj ship --bookmark main --tag v0.2.1 --no-sign
```

## Publish an already-created tag

```bash
jj tag-push v0.2.1 --revision main
```

`jj tag-push` exists because jj aliases cannot add `jj tag push` under the
built-in `jj tag` command. Do not expect `jj git push --all` to create new
remote tags; jj intentionally refuses that.

By default `jj tag-push` creates the annotated tag message as
`<repo-name> <tag>`. Override it when needed:

```bash
jj tag-push v0.2.1 --revision main --message "project v0.2.1"
```

Force signing or unsigned mode explicitly when needed:

```bash
jj tag-push v0.2.1 --revision main --sign
jj tag-push v0.2.1 --revision main --no-sign
```

Signed tags are annotated tags. The helper verifies newly-created signed tags
with `git verify-tag` before pushing. If signing fails because GPG or pinentry is
not ready, fix the GPG environment or rerun with `--no-sign` to create an
unsigned annotated tag.

The helper shells out to Git with `--git-dir "$(jj git root)"` instead of relying
on a colocated `.git`, so signing works from non-colocated jj workspaces as well
as main checkouts.

## Why annotated tags matter

`jj tag set` creates lightweight tags. Some release hosts, including sourcehut's
release-artifact flow, only attach artifacts to annotated tags. A lightweight
tag can make `hut git artifact upload --rev <tag>` appear to succeed while the
artifact is not downloadable.

Fingerprint a remote tag with `git ls-remote --tags <url> refs/tags/<tag>`:

- annotated tag: two lines, `refs/tags/<tag>` plus `refs/tags/<tag>^{}`
- lightweight tag: one line only

If `jj tag-push` sees an existing remote lightweight tag at the requested commit,
it stops instead of silently treating the tag as published. Re-create the remote
tag as annotated on the same commit, then force-push only `refs/tags/<tag>`.
