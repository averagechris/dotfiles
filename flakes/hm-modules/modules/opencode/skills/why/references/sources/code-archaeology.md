# Code archaeology

## What to search

Search commit messages, diffs, PR bodies and reviews, comments, tests, release notes, and related files changed in the same commits. These records are close to the shipped code, but they still may omit or misstate intent.

Use the configured VCS and prefer `jj` in jj repositories. Read the applicable skill and command help for line attribution, rename-aware file history, patches, descriptions, and exact-text history. Use `git` only in a non-jj repository.

For substantive commits, use `gh` or the available forge interface to read the full PR:

```bash
gh pr view <number> --json title,body,author,createdAt,mergedAt,labels,closingIssuesReferences,comments,reviews,files
```

Search nearby repository records:

```bash
rg -n -C2 '(TODO|FIXME|HACK|XXX|NOTE)' <target_file>
rg -l '<symbol>' --glob '*test*'
rg -l -i 'architecture.decision' --glob '*.md'
```

Trace copied patterns to their first introduction. Follow ticket, incident, commit, and PR IDs as leads.

## Strong evidence

- a PR description naming the problem
- a review debating alternatives
- a comment explaining a non-obvious constraint
- a test that names the motivating edge case
- a commit or release note linking a ticket or incident

## Failure modes

Squash merges can erase branch commits, so use PR discussion. Commit subjects may minimize behavior changes, so inspect diffs. Skip bot-only updates when seeking intent. A copied pattern may preserve no deliberate choice by the current author. Code and symbol names show mechanics, not motivation.

## Return

For each relevant record, provide the quote, hash or PR number or file line, author, date, and whether it directly states a reason or only supports one.
