---
name: test-curation
description: |
  Use when finalizing a code change or PR after tests were added or changed, to
  decide what deserves permanent retention. Do not use for non-code work,
  initial test planning, ordinary tasks without test changes, or generic
  implementation.
---

# Curate changed tests

A check useful during development does not automatically deserve to ship.
Review only tests added or materially changed in the change being finalized.

## Decide what remains

Keep tests that:

- protect meaningful behavior through a stable boundary
- catch a plausible, durable regression
- justify their ongoing maintenance and CI cost

Preserve meaningful rendered-configuration and contract tests. Do not chase a
target test count or remove valuable tests merely to make the suite faster.

Remove tests that merely mirror configuration literals or props, trivial
helpers or branches, implementation details, framework or type guarantees, or
temporary scaffolding when they do not meet the retention bar. Development-only
manual scripts and temporary checks may be deleted without converting them to
permanent tests.

## Finalize the change

When loaded for read-only review, report which changed tests should remain or be
removed and why. Do not edit unless the handoff explicitly authorizes
implementation.

When asked to finalize the change:

1. Inspect the tests added or materially changed in scope.
2. Make the justified removals while retaining tests that meet the bar.
3. Rerun the smallest relevant checks for the resulting change.
4. Report what was kept and removed, and why.
