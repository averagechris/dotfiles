---
name: suremac-jj-pr
description: Use when creating, updating, closing, watching, commenting on, requesting review for, or sweeping GitHub PR hygiene from jj workspaces on suremac work repos. Prefer `jj pr` over bare `gh pr create`; covers PR body style, review comments and replies, reviewer tagging, jj remotes, bookmarks, sync, lints, push, CI, review polling, and open-PR follow-up reports.
---

# Suremac jj PR Workflow

Use this skill on `suremac` when the user asks to create, update, close, watch,
prepare, or sweep hygiene/follow-up for GitHub pull requests from jj workspaces,
especially for work repositories under `~/sureapp`.

## Core rule

Do **not** run bare `gh pr create` from jj workspaces. Use the repo-managed helper:

```bash
jj pr doctor
jj pr create ...
jj pr update ...
jj pr close ...
jj pr hygiene
```

The helper infers the GitHub repository from `jj git remote list` and always calls GitHub CLI commands with explicit `--repo owner/repo`, which works in non-colocated jj workspaces where `gh pr create` cannot discover `.git`.

## Standard create flow

1. Inspect current state:

   ```bash
   jj pr doctor
   ```

   Use JSON for scripts or when you need stable fields:

   ```bash
   jj pr doctor --json
   ```

2. Ensure there is a suitable jj bookmark at `@`. `jj pr create` intentionally
   does not infer an ancestor bookmark for creation because that can omit the
   current work. If none exists, pass a ticket so `jj pr create` can auto-create
   one from the configured template:

   ```text
   {whoami}/{ticket-number}/{short-description}
   ```

3. Create the PR with explicit body input:

   ```bash
   jj pr create \
     --base develop \
     --sync \
      --run-lints \
     --ticket EPD-1234 \
     --title "fix(policy): concise change summary [EPD-1234]" \
     --body-file /tmp/pr-body.md
   ```

   Notes:
   - `--sync` runs `jj sync --onto <base>@<inferred-remote> --fail-on-conflicts` before checks, usually with `origin`.
   - `--run-lints` runs `jj lint`.
   - Push is enabled by default. Use `--no-push` only when explicitly needed.
   - Add `--draft` for draft PRs.
   - `--dry-run` plans auto-bookmarking without creating the bookmark.
   - Use `--remote <remote>` when the push/sync remote cannot be inferred or when `--repo owner/repo` is explicit and multiple/no matching jj remotes exist.

Auto-created bookmarks are durable. If a later sync, lint, push, or GitHub step fails, leave the bookmark in place and resume from it. Ticket values for auto-bookmarking must be simple safe identifiers using only letters, numbers, dot, underscore, or hyphen.

Before creating a PR, the helper checks the PR-relevant stack for conflicts and
requires the current change to have a jj description. If it reports an empty
description, run `jj describe -m "<conventional commit message>"` before
retrying.

## Writing the PR body

PR bodies are for human reviewers deciding whether to trust and merge the
change. Explain the problem and why this solution; never narrate the diff.

Structure, in order (omit sections that genuinely do not apply):

1. **Problem** — why this PR exists. What is broken, slow, risky, or missing,
   and who/what it affects. If you cannot state a problem, question the PR.
2. **Fix / Change** — the shape of the solution and why this approach, in a
   few plain sentences. Layer detail: short summary first, mechanism after.
   Reviewers read the diff for the "what"; give them the "why" and the
   non-obvious decisions.
3. **Result / Impact** — quantify when possible (latency deltas, CI minutes
   saved, counts). State explicit non-goals and scope guards: "this does not
   deploy anything", "the image-pull delay is out of scope".
4. **Safety / Rollout** — only for risky or user-visible changes: fallback
   behavior, flags, rollout order, cross-repo merge order with PR links.
5. **Verification** — what was verified, in outcome terms ("full suite: 1046
   passed; strict mypy clean"), not raw command dumps with env vars. Disclose
   honestly anything that could not be run and why. Where behavioral evidence
   would genuinely help the reviewer, add it per the section below.

Rules:

- Lead with the problem in prose, not a bullet list of diff restatements.
- Link the Linear ticket once as a real link with context, e.g.
  `Fixes [EPD-1234](https://linear.app/sureapp/issue/EPD-1234/slug)` near the
  top. Do not scatter `Tracking:`/`Linear:` variants.
- Do not repeat the PR title as a heading inside the body.
- No agent-workspace narration ("in this managed workspace", "artifacts were
  not committed", devenv/sandbox limitations). If a check could not run, state
  the reviewer-relevant fact plainly ("Vitest not run: no Node in the build
  environment") without workflow autobiography.
- Proofread the final body: no tool-call debris, stray flags, or truncated
  lines. Read it back after `jj pr create`/`update` if there is any doubt.
- Keep evidence proportional: digests, sha256 values, and long logs belong in
  a comment or the ticket, not the body.

## Verification evidence

Unit tests prove the code; evidence proves the behavior. Match the evidence to
the risk and skip it where it adds nothing: dependency bumps, config tweaks,
refactors, and doc changes usually need no more than their passing checks.
Spend evidence effort where the reviewer would otherwise have to trust or
reproduce the change themselves — user-visible behavior, tricky logic,
performance claims, security-sensitive paths.

Cheap, creative verifications are welcome as long as they are proportional to
the risk: a one-liner curl against a running service, a focused script whose
trimmed output shows the before/after, a log line proving the new code path
ran. Full-stack verification with `suremise` (the local full-stack k8s CLI) is
the heavyweight option for changes that warrant it; load `suremise-test-change`,
`suremise-e2e`, or `suremise-evidence` for the mechanics and prefer the
smallest workflow that proves the behavior.

When evidence is worth including:

- **UI/UX changes**: before/after screenshots or a short video — Playwright
  artifacts from `suremise verify`, or a browser screenshot of the running
  local stack. GitHub uploads cannot be done from the CLI, so save artifacts
  to a stable local path and give chris the paths to drag into the PR, or link
  CI-collected artifacts when the run happened in CI. Name files
  descriptively (`admin-portal-before.png`), not `screenshot-1.png`.
- **Backend changes**: replayable evidence — the exact request and trimmed
  response (curl + JSON), the relevant log lines, or the state before/after.
  When it helps, add a short "How to verify" snippet: the two or three
  commands a reviewer would run to see the same result.
- One artifact that shows the fix beats a checklist of commands. Trim output
  to the lines that matter; long transcripts go in a comment or the ticket.
- If meaningful verification was warranted but not possible, say so plainly in
  Verification rather than substituting unit-test output for behavioral
  evidence.

## PR comments and review replies

When commenting on a PR or replying to review threads on chris's behalf, start
every comment with an attribution line:

```markdown
`<model name> <model version> commenting on behalf of chris`
```

Use `responding` instead of `commenting` when replying to a person. Fill in
your actual model name and version (e.g. `claude fable 5`).

Tone and content rules:

- Simple technical language, simple grammar. Short sentences.
- Chill but very direct. No fluff, no hedging, no "great point!" filler, no
  apologies, no emoji.
- Answer the question first, context after. One comment per concern.
- Use GitHub suggestion blocks (```suggestion) whenever proposing a concrete
  small code change on a review thread, so it is one-click applicable.
- Disagree plainly with a reason and evidence. If accepting, say what will
  change and where.
- Reply on the thread (`gh api` review-comment reply endpoints or
  `gh pr comment` for top-level) with explicit `--repo owner/repo`.

## Requesting reviewers

Resolve colleague names through the cached reviewer mapping instead of
re-discovering identities each time:

```bash
jj pr reviewers list
jj pr reviewers resolve <name>
jj pr reviewers add <name> --github <handle> [--linear <id>] [--alias <alt>]...
```

Then tag reviewers at create/update time with `--reviewer <name-or-handle>`
(repeatable), or `gh pr edit --repo owner/repo --add-reviewer <handle>` for an
existing PR.

On a resolve miss: discover the person once (e.g. `gh api` user search, recent
PR authorship in the repo, or the Linear CLI), confirm with the user if
ambiguous, then `jj pr reviewers add` so the lookup never repeats. The mapping
lives in `$XDG_CONFIG_HOME/jj-workflow/reviewers.toml`, falling back to
`~/.config/jj-workflow/reviewers.toml`, and is intentionally not checked into
dotfiles.

## Existing PRs

`jj pr create` fails loudly if an open PR already exists for the head bookmark. Do not create duplicates.

Update only requested fields:

```bash
jj pr update --title "fix(policy): updated title [EPD-1234]"
jj pr update --body-file /tmp/pr-body.md
jj pr update --base main
```

Close the GitHub PR only; local jj bookmarks and changes are left untouched:

```bash
jj pr close
```

## CI and review watch

Use `jj pr watch` instead of dumping raw CI logs or full review threads into the
agent context:

```bash
jj pr watch
jj pr watch --interval 60s --timeout 30m
jj pr watch --once --json
```

The helper polls GitHub checks, unresolved review threads, and review decisions.
It prints a compact summary with check counts, failing checks plus links,
pending checks, review decision, and first lines/permalinks for unresolved review
comments. It treats empty check lists as pending, exits 0 only when checks pass
and no unresolved comments/blocking review decisions remain, and exits nonzero
when checks fail, `CHANGES_REQUESTED` is present, comments need attention, or
`--once` observes a pending state. With `--json` in polling mode it emits
newline-delimited JSON snapshots.

If the PR is already closed or merged, `jj pr watch` reports that state directly
and exits nonzero; do not treat stale check output from closed PRs as active work.

Use the printed links or `gh` directly only when detailed logs/full comments are
needed. Prefer `--ignore-comments` only when the user explicitly wants to gate on
CI checks alone.

## PR hygiene sweep

When the user asks to catch up on open PRs, run PR follow-up hygiene next to the
Linear hygiene loop:

```bash
github-pr-hygiene-report
github-pr-hygiene-report --force
github-pr-hygiene-report --json
```

Prefer `github-pr-hygiene-report` for normal on-demand follow-up: it reads the
scheduled cache when it is fresh and refreshes only after the TTL expires or the
requested search, limit, TTL, workdir list, or `--no-workspaces` flag differs from the cached inputs. Use
`github-pr-hygiene-report --force` when the user explicitly wants a fresh GitHub
query now, and `github-pr-hygiene-report --json` for stable cached fields. The
shell prompt reads the same cache locally with `jq`, so prompt rendering does
not start Python or hit GitHub/jj.

The lower-level `jj pr hygiene` command searches open GitHub PRs authored by the current GitHub user
(default search: `author:@me is:pr is:open archived:false`), enriches them with
checks, review decision, unresolved comments, size, and base/head branch data,
then scans configured jj workspace roots for related local workspaces. The human
report includes links, status, review effort estimate, heuristic priority, a
suggested follow-up, and a copyable reviewer nudge for PRs that are green and
waiting for review.

Use direct `jj pr hygiene` only when you intentionally want an uncached GitHub
query from inside a jj repo. The cached wrapper exists because scheduled launchd
and shell workflows may start outside any particular jj checkout; it finds a
configured jj workdir, keeps the shared cache fresh, and avoids hitting GitHub
from prompts.

Use it before telling the user what to complain about. Prefer these outcomes:

- `needs-fix`: fix CI/review comments before asking people for more review.
- `ready`: merge or hand off the merge decision.
- `needs-review`: nudge reviewers, including the effort estimate and PR link.
- `waiting-ci`: wait or inspect CI; do not ask humans before checks are green.
- `draft`: finish or mark ready before requesting review.

Use `--search <github-search>` to narrow scope, `--limit <n>` for shorter sweeps,
and `--no-workspaces` if local workspace discovery is slow or irrelevant. The
cached wrapper also keys freshness on the TTL and configured workdir strings. Use
`--json` when another script/agent needs stable fields.

## Follow-up changes after CI/review

When CI or GitHub review feedback needs code changes, make a new jj change on top, move the PR bookmark intentionally, and push again:

```bash
jj new @
# edit files
jj describe -m "fix(scope): address PR feedback"
jj bookmark set <pr-bookmark> -r @
jj lint
jj git push --bookmark <pr-bookmark>
```

Do not raw-push a feedback change before `jj lint` succeeds. If the repository's
canonical `jj push` helper targets the intended bookmark and preserves the same
semantics, prefer it because it runs the lint gate before pushing.

Then re-check the PR with GitHub/CircleCI tools as appropriate.

## Failure handling

- If `jj pr create` reports an existing PR, use `jj pr update` or ask the user whether to close/update it.
- If push fails due to remote bookmark divergence, do not force-push automatically. Read the helper hints and ask if destructive/update semantics are needed.
- If sync reports conflicts, load `jj-conflict-resolution` and resolve before continuing.
