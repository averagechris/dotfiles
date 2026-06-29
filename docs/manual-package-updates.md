# Manual package updates

Most dependencies in this repository are flake inputs and are updated through
lockfiles. A small set of tools is intentionally packaged from fixed upstream
release archives or pinned source revisions instead. The update metadata for
those packages lives in:

```text
manual-package-updates.json
```

The manifest is data-driven. Set a package's `enabled` field to `false` to
unenroll it persistently from automated manual-package update runs. For one-off
runs, use `--skip-manual-package` or select a single package with
`--manual-package`.

## Running updates

The main updater is a Rust tool exposed by the top-level flake and installed in
the dev shell:

```bash
update-flakes --check
update-flakes
```

Outside the dev shell, use the flake app:

```bash
nix run .#update-flakes -- --check
nix run .#update-flakes
```

By default, the updater handles both flake inputs and manifest-enrolled manual
packages. Use these flags to change scope:

```bash
update-flakes --no-manual-packages          # flake inputs only
update-flakes --manual-packages-only        # manual packages only
update-flakes --manual-package helium-bin   # one manual package only
update-flakes --skip-manual-package pi-coding-agent
```

For upstreams without reliable latest-release metadata, provide the reviewed
target version explicitly:

```bash
update-flakes --manual-packages-only \
  --manual-package coderabbit-cli \
  --manual-version coderabbit-cli=0.6.1
```

The updater prefetches the manifest's release asset URLs with
`nix store prefetch-file --json` and rewrites the package `version` plus fixed
hashes in the referenced Nix file.

By default, `update-flakes` captures noisy child command output and prints only a
compact progress summary plus actionable skips or failures. Pass `--show-output`
or set `UPDATE_FLAKES_SHOW_OUTPUT=1` to stream full `nix flake update` output
when debugging.

## Cooldowns

Manual package updates share the same default cooldown window as fast-moving
flake inputs: 7 days unless overridden with `--cooldown-days` or
`FLAKE_UPDATE_COOLDOWN_DAYS`. The default gated flake inputs are `pi` and
`pi-coding-agent`; override the whole list with `--cooldown-inputs` or
`FLAKE_UPDATE_COOLDOWN_INPUTS`. Manifest packages opt into cooldowns with
`"cooldown": true` and can override the global day count with `"cooldownDays"`.
GitHub-release packages use release `published_at` timestamps and select the
newest non-prerelease version that is at least the cooldown age; a newer release
inside the cooldown window does not block updating to an older cooldown-safe
release. Explicit `--manual-version` updates log a warning when release age
cannot be determined; only use explicit versions after manual release review.

Use `--ignore-cooldown` only after reviewing fresh upstream releases.

## Currently tracked manual packages

| Package | File | Status |
| --- | --- | --- |
| `pi-coding-agent` / `pi` | `flakes/base-lib/packages/pi-coding-agent.nix` | Enabled; latest version from GitHub releases |
| `coderabbit-cli` | `flakes/base-lib/packages/coderabbit-cli.nix` | Enabled; requires explicit `--manual-version` |
| `notion-cli` | `flakes/base-lib/packages/notion-cli.nix` | Enabled; requires explicit `--manual-version` |
| `helium-bin` | `flakes/base-lib/packages/helium-bin.nix` | Enabled; latest version from GitHub releases |
| `pup` | `flakes/base-lib/packages/pup.nix` | Enabled; requires explicit `--manual-version` |
| `rodney` | `flakes/base-lib/packages/rodney.nix` | Manifest entry is disabled; Go `vendorHash` automation not enabled yet |
| `showboat` | `flakes/base-lib/packages/showboat.nix` | Manifest entry is disabled; Go `vendorHash` automation not enabled yet |

`rodney` and `showboat` live in separate package files so they can be enrolled
later without refactoring the overlay, but their Go `vendorHash` update loop is
not automated yet.
