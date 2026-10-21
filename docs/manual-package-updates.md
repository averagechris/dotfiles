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
| `notion-cli` | `flakes/base-lib/packages/notion-cli.nix` | Enabled; requires explicit `--manual-version` |
| `helium-bin` | `flakes/base-lib/packages/helium-bin.nix` | Enabled; latest version from GitHub releases |
| `pup` | `flakes/base-lib/packages/pup.nix` | Enabled; requires explicit `--manual-version` |
| `showboat` | `flakes/base-lib/packages/showboat.nix` | Manifest entry is disabled; Go `vendorHash` automation not enabled yet |

`showboat` lives in a separate package file so it can be enrolled later without
refactoring the overlay, but its Go `vendorHash` update loop is not automated
yet.

## Maintained fork inputs

The 2026-10-09 fork review updates pin `ctx`, `hister`, `linear-cli`,
`starship-jj`, and `zeroclaw` to their merged upstream-review changes. Keep
these revisions consistent in the root lock and every standalone host or
shared-module lock that consumes them. ZeroClaw also has an explicit revision
in `flakes/hosts/thorny/flake.nix`; advance that URL when updating its lock.
Slack is no longer a dotfiles flake input.

## eMudhra certificate mitigation (2026-10-20)

Keep the shared `nixpkgs` input pinned to
`e4d4e5154c52da44a9e5a4895d270cffa1ecb6fc` until the `nixos-unstable` channel
includes both the `cacert` 3.131.1 and uv 0.13.4 fixes. The channel revision
`02c087f3fe673c9e317f206a627cb6b910336dbe` contains the NixOS system
certificate blacklist, but predates that `cacert` fix, which is needed by
Darwin and direct `pkgs.cacert` consumers. Keep `original.ref = "nixos-unstable"`
and make all 14 canonical lockfiles use the same pinned revision. This snapshot
also includes the [System76 module installation fix](https://github.com/NixOS/nixpkgs/pull/575724)
needed for thorny to build with the newer kernel module certificate checks.

OpenCode remains at its previously validated source revision. Its Darwin
`node_modules` hash is refreshed for the updated Bun version in both package
overlays; see [OpenCode patch lifecycle](opencode-patches.md).

The normal updater advances this input to the current channel, so do not update
the shared `nixpkgs` pin until the channel has the fix. Before lifting the pin,
verify the `cacert` version and repeat the certificate checks against both the
direct endpoint and Sectigo cross-sign endpoint:

```bash
for endpoint in \
  https://dv-g3b-emudhra.we-have-a-problem.com/ \
  https://dv-g3b-aaa-emudhra.we-have-a-problem.com/; do
  if curl --cacert /etc/ssl/certs/ca-certificates.crt \
    --silent --show-error --output /dev/null "$endpoint"; then
    echo "unexpected TLS success: $endpoint" >&2
    exit 1
  else
    status=$?
    test "$status" -eq 60 || exit "$status"
  fi
done
```

Both checks pass only when curl rejects the certificate with error 60. Network
or DNS errors do not pass. The eMudhra advisory homepage is a healthy HTTPS
site, so do not use it as a rejection test. Run this after the target system
bundle has been updated. Repeat the same check with
`--cacert /etc/nix/macos-keychain.crt` to check the Nix daemon's separately
exported macOS Keychain bundle. Updating the system bundle does not update that
file. An input update alone does not prove every Nixpkgs-managed or
application-bundled trust store has the fix.
Nixpkgs tracks its bundled certificate updates in
[issue #576475](https://github.com/NixOS/nixpkgs/issues/576475).

This mitigation follows the
[eMudhra advisory](https://emudhra.we-have-a-problem.com/) and the nixpkgs
fixes in [PR #576390](https://github.com/NixOS/nixpkgs/pull/576390) and
[PR #576347](https://github.com/NixOS/nixpkgs/pull/576347). Nixpkgs-managed
bundled certificates need separate verification after the pin changes.
Manually installed browsers such as Helium and Chrome have separate update
paths and may need an update and restart before their trust state changes.
