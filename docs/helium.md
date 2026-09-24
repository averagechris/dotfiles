# Helium browser

This repository packages the upstream Helium Linux binary tarball for NixOS via Home Manager.
The current package version is 0.17.2.1.
The package derivation lives at `flakes/base-lib/packages/helium-bin.nix` and is
exposed as `pkgs.helium-bin` by the shared base-lib overlay.

## Configuration

Enable Helium in a host's Home Manager configuration:

```nix
programs.helium.enable = true;
```

The module currently:

- installs an `x86_64-linux` wrapper around the upstream Helium binary tarball
- patches bundled binaries for NixOS with `autoPatchelfHook`
- installs a desktop entry and icons
- registers Helium as a browser handler for HTTP/HTTPS and HTML content

## Simple PiP Helper extension

The `tater` and `thorny` host flakes include the Simple PiP Helper Chromium
extension from <https://github.com/averagechris/pip-chrome-extension> and import
its Home Manager module next to the shared dotfiles module:

```nix
imports = [
  inputs.hm-modules.homeManagerModules.default
  inputs.pip-chrome-extension.homeManagerModules.default
];

programs.helium.enable = true;
programs.helium.extension-simple-pip-helper.enable = true;
```

The external module links the unpacked extension into
`$XDG_CONFIG_HOME/net.imput.helium/simple-pip-helper`. After the first rebuild,
open Helium's extensions page, enable Developer mode, choose **Load unpacked**,
and select that stable symlink path. Helium should remember the extension across
later Home Manager rebuilds.

## nitter-link extension

The reusable `programs.nitter-link` Home Manager module pins
<https://github.com/averagechris/nitter-link> at `v0.1.4` and consumes its
reproducible flake package outputs (`chrome-extension` and `firefox-extension`).
Those packages install browser-loadable unpacked trees below
`$out/share/nitter-link/chrome` and `$out/share/nitter-link/firefox`; the module
links those directories rather than the package root.

For Helium, the module exposes the unpacked Chromium extension through a stable
Home Manager-managed symlink. Load that stable path once from the browser's
extensions UI; later rebuilds update the symlink target without changing the
browser-visible path, preserving browser identity/settings and avoiding browser
process management. Current host paths are:

- `tater`: `$XDG_CONFIG_HOME/net.imput.helium/nitter-link`
- `suremac`: `$XDG_CONFIG_HOME/net.imput.helium/nitter-link`

Zen/Firefox integration is deliberately conservative. The module does not edit
profiles, `extensions.json`, SQLite databases, or unsigned enterprise policy
installs. On `tater`, an explicitly temporary/manual option exposes the unpacked
Firefox tree at `$XDG_CONFIG_HOME/zen/nitter-link-temporary` for manual testing.
To load it in Zen:

1. Open `about:debugging#/runtime/this-firefox`.
2. Choose **Load Temporary Add-on...**.
3. Select `$XDG_CONFIG_HOME/zen/nitter-link-temporary/manifest.json`.

This keeps the upstream Gecko extension ID from the manifest intact, but it is a
temporary development-style install: Zen will remove it on browser restart. A
permanent declarative install should wait for a signed XPI and a verified
Zen-supported policy or Home Manager mechanism.

## Why a wrapped binary package?

Helium does not appear to have a mature NixOS package upstream, and its Linux AppImage/update path has rough edges on non-FHS systems. This repo therefore packages the upstream binary tarball declaratively so it can run reliably on NixOS.

## Updating Helium

To update Helium, prefer the manifest-driven updater:

```bash
update-flakes --manual-packages-only --manual-package helium-bin
```

Manual updates should bump the version and hash in:

`flakes/base-lib/packages/helium-bin.nix`

Use the latest release from:

- <https://github.com/imputnet/helium-linux/releases/latest>

Update both:

- the tarball URL/version
- the `sha256` hash from the release asset digest

## Notes

- The current package targets `x86_64-linux`.
- The wrapper sets `CHROME_VERSION_EXTRA=NixOS` so upstream bug reports clearly identify the distribution method.
