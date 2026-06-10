# jj Tag Workflow

Human/agent-created release tags are opt-in. Repos whose CI/CD creates tags do
not need this workflow.

## Ship and tag together

```bash
jj ship --bookmark main --tag v0.2.1
```

`jj ship --tag` tags the exact commit that `jj ship` published, exports refs to
colocated Git, pushes `refs/tags/<tag>` to the selected remote, and verifies the
remote tag.

## Publish an already-created tag

```bash
jj tag-push v0.2.1 --revision main
```

`jj tag-push` exists because jj aliases cannot add `jj tag push` under the
built-in `jj tag` command. Do not expect `jj git push --all` to create new
remote tags; jj intentionally refuses that.
