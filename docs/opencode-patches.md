# OpenCode patch lifecycle

The Home Manager OpenCode module applies repository-owned patches to the source
from the pinned `github:anomalyco/opencode/v2` flake input. The package is pinned
at revision `8eff035bf45342bda2d37a884df1191cd9bf3e62`, OpenCode 2.0.26. The patch
list lives in `flakes/hm-modules/modules/opencode/default.nix`, and patch files
live beside the module under `patches/`.

Run `scripts/check-opencode-patches.sh` after changing a patch or updating the
OpenCode input. It dry-runs every patch against the locked source and reports
whether each patch is needed, stale because upstream contains it, or broken by
upstream drift. Applicability is not behavior evidence. Run the focused upstream
test carried by a patch and build the patched Home Manager package.

## Active patches

There are no active patches.

The retired environment-assignment patch stripped static assignment prefixes
from permission resources produced by the legacy shell scanner. OpenCode's
compatibility contract instead requires the legacy and portable scanners to
produce the same raw resource, including the assignment prefix. The patch broke
that parity. It could also expose commands that run during assignment expansion
before the named executable, including Bash prompt and arithmetic expansions,
to a rule intended only for that executable. The module now keeps upstream's
raw permission resource and does not normalize environment-prefixed commands.

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

OpenCode 2.0.26 canonicalizes module links and normalizes Bun binaries before
installation. The direct-to-output trees match upstream's fixed-output hashes
for x86_64-linux, aarch64-linux, and aarch64-darwin, so the old platform hash
overrides are removed. ARM dependency trees were generated on Linux using Bun's
explicit CPU/OS selection; this does not validate native ARM executables. The
module inherits upstream's platform hashes. The direct-to-output install override
remains to avoid the second recursive copy.

To verify the Linux package without building the host system closure:

```sh
direnv exec . nix build --no-link \
  '.#nixosConfigurations.thorny.config.home-manager.users.chris.programs.opencode.package'
```

On Darwin, build the suremac package:

```sh
direnv exec . nix build --no-link \
  '.#darwinConfigurations.suremac.config.home-manager.users.chris.programs.opencode.package'
```

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
