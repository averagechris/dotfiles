# OpenCode patch lifecycle

The Home Manager OpenCode module applies repository-owned patches to the source
from the pinned `github:anomalyco/opencode` flake input. The patch list lives in
`flakes/hm-modules/modules/opencode/default.nix`, and the patch files live beside
the module under `patches/`.

Run `scripts/check-opencode-patches.sh` after changing a patch or updating the
OpenCode input. It dry-runs every patch against the locked source and reports
whether each patch is still needed, has become stale because upstream contains
it, or is broken by upstream drift. A successful dry-run proves applicability,
not runtime behavior; run the smallest relevant upstream test when a patch
contains regression coverage.

## Active patches

- `opencode-route-nested-prompts.patch` makes the root TUI collect pending
  permission and question requests from its complete descendant session tree.
  OpenCode 1.18.18 only inspects the root and direct children, so a grandchild's
  request is invisible and can stall a nested agent chain. The patch is a minimal
  adaptation of the TUI portion of upstream issues
  [#13715](https://github.com/anomalyco/opencode/issues/13715) and
  [#39112](https://github.com/anomalyco/opencode/issues/39112), and PR
  [#36046](https://github.com/anomalyco/opencode/pull/36046), with focused
  subtree traversal tests in the patched upstream TUI package.
- `opencode-strip-env-assignments.patch` normalizes safe leading environment
  assignments before matching bash permission patterns.
- `opencode-allow-nix-bun-1-3-13.patch` permits the Bun 1.3 patch release
  supplied by nixpkgs when it differs from upstream's exact declaration.
- `opencode-fix-old-drizzle-migration-journal.patch` migrates older Drizzle
  journals that predate the journal `name` column without replaying completed
  SQL migrations.

## Removal criteria

Review patches whenever the pinned OpenCode revision changes. Remove a patch
when the pinned source contains an equivalent fix and the relevant behavior has
been verified without it.

Specifically, remove `opencode-route-nested-prompts.patch` once either:

1. the upstream OpenCode version pinned by this repository fixes complete-tree
   routing for both nested permission and nested question requests; or
2. OpenCode v2 actually launches, this repository switches to it, and equivalent
   nested permission/question routing has been verified there.

An announcement or planned v2 architecture alone is not sufficient for the
second criterion.
