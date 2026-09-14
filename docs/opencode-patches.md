# OpenCode patch lifecycle

The Home Manager OpenCode module applies repository-owned patches to the source
from the pinned `github:anomalyco/opencode/v2` flake input. The package is pinned
at revision `76594882b4a9a6a14dd4f99b515d4aba2d5e6f16`, OpenCode 2.0.3. The patch
list lives in `flakes/hm-modules/modules/opencode/default.nix`, and patch files
live beside the module under `patches/`.

Run `scripts/check-opencode-patches.sh` after changing a patch or updating the
OpenCode input. It dry-runs every patch against the locked source and reports
whether each patch is needed, stale because upstream contains it, or broken by
upstream drift. Applicability is not behavior evidence. Run the focused upstream
test carried by a patch and build the patched Home Manager package.

## Active patch

`opencode-strip-env-assignments.patch` ports the v1 environment-assignment
normalization to v2's legacy shell scanner in
`packages/core/src/shell/parse.ts`. Static prefixes such as
`SERVICE_PORT=51820 just test` authorize the `just test` resource and therefore
match normal `just *` policy. Prefixes containing command or process
substitutions remain part of the permission resource. The scanner also emits the
nested command as a separate resource, so `TOKEN=$(curl example.test) just test`
cannot inherit a plain `just *` approval.

The patch includes focused `packages/core/test/shell-parse.test.ts` cases for
static assignments, `$()` substitutions, backticks, and process substitutions.
The experimental portable shell scanner has its own parser and does not use this
normalization. Remove the patch when upstream normalizes safe assignments in
both scanners, or port the same safety rule before enabling the portable scanner
in this repository.

## Retired v1 patches

The v2 migration removes three v1 patches:

- Bun tolerance is upstream in `nix/opencode.nix`. The derivation changes the Bun
  version mismatch from an error to a warning, and the package builds with
  nixpkgs Bun 1.3.13 while upstream declares Bun 1.4.2.
- Nested permission and question routing is native in v2. The root TUI uses
  `data.session.family(rootID)` and gathers both `permission.list(sessionID)` and
  `form.list(sessionID)` across the complete family. Upstream's transport test
  `recursively hydrates blockers for direct and transitive descendants` covers
  a grandchild form, while the same transport hydrates permissions for every
  recursively discovered child. The v1 `packages/tui` patch targeted code and
  SDK types that no longer own this behavior.
- The old Drizzle journal workaround is not carried forward. V2 has explicit
  tests that import unnamed journal rows by their timestamp and reject unknown
  timestamps instead of guessing that the first N migrations completed. Keeping
  the old count-based fallback would weaken that migration safety check.

## Local node-modules derivation override

V2's `nix/node_modules.nix` now reads `packages/cli/package.json` and filters the
install for `packages/cli`, but its install phase still recursively copies every
completed `node_modules` tree. The Home Manager module therefore retains the
direct-to-output override. It injects a copy to `$out` immediately after the
upstream cache-directory setup, runs the inherited build there, then removes
non-module files and empty directories.

The marker assertion requires one exact upstream setup line, so build-phase
drift fails evaluation. `scripts/check-opencode-node-modules-install.sh` compares
the transformed install with the old install using nested modules, symlinks, and
an executable fixture. Remove the override once upstream installs directly into
the output, or once an upstream replacement passes the same output-equivalence
check.

The old per-revision node-module hashes and ghostty lockfile fix are gone. V2's
`nix/hashes.json` supplies the aarch64-darwin hash for this revision and the
package builds without either override.

## Update checklist

When the pinned OpenCode revision changes:

1. Confirm every lock graph that contains the OpenCode input has the same v2
   revision and only the OpenCode node changed.
2. Run `scripts/check-opencode-patches.sh` and the focused upstream tests from
   each active patch.
3. Run `scripts/check-opencode-node-modules-install.sh` while the local install
   override remains.
4. Build the actual Home Manager package for aarch64-darwin and run `--version`
   with isolated `HOME` and XDG directories. Do not activate the configuration
   as part of package validation.
