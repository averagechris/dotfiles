# Helium Browser

This repository packages the upstream Helium Linux binary tarball for NixOS via Home Manager.
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
extension from <https://git.sr.ht/~averagechris/pip-chrome-extension> and import
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
