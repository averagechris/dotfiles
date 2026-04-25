# Helium Browser

This repository packages the upstream Helium Linux binary tarball for NixOS via Home Manager.

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

## Why a wrapped binary package?

Helium does not appear to have a mature NixOS package upstream, and its Linux AppImage/update path has rough edges on non-FHS systems. This repo therefore packages the upstream binary tarball declaratively so it can run reliably on NixOS.

## Updating Helium

To update Helium, bump the version and hash in:

`flakes/hm-modules/modules/gui/helium.nix`

Use the latest release from:

- <https://github.com/imputnet/helium-linux/releases/latest>

Update both:

- the tarball URL/version
- the `sha256` hash from the release asset digest

## Notes

- The current package targets `x86_64-linux`.
- The wrapper sets `CHROME_VERSION_EXTRA=NixOS` so upstream bug reports clearly identify the distribution method.
