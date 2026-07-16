# Flake Size and Evaluation Hygiene

The top-level flake is an aggregator over per-host path flakes. When adding a
new host flake or shared module flake input to `flake.nix`, make its local shared
inputs follow the root inputs instead of letting Nix lock another copy of the
same `path:` flake and its transitive graph.

For host flakes, prefer this shape:

```nix
host = {
  url = "path:./flakes/hosts/host";
  inputs.base-lib.follows = "base-lib";
  inputs.nixos-modules.follows = "nixos-modules";
  inputs.hm-modules.follows = "hm-modules";
};
```

Darwin hosts should follow `darwin-modules` instead of `nixos-modules` when they
import it. If a host pins a package flake that is already exposed by `hm-modules`
(for example `starship-jj`, `linear-cli`, or `gander`), make the host input
follow the `hm-modules/...` input so the root lock keeps one node.

Standalone host flakes should also make their local module path flakes follow the
host's own shared graph. In a NixOS host flake, `nixos-modules.inputs.base-lib`
should follow `base-lib`; `nixos-modules.inputs.nixpkgs` should follow `nixpkgs`;
and `hm-modules` should follow the host's `base-lib`, `nixpkgs`, `flake-utils`,
`home-manager`, and `base-lib/opencode` inputs. This keeps commands such as
`nix flake check ./flakes/hosts/thorny --no-build` from locking a second copy of
the shared module stack.

For standalone shared module flakes, prefer following `base-lib`'s graph rather
than declaring a second root copy of common framework inputs. For example,
`hm-modules` follows `base-lib/nixpkgs`, `base-lib/flake-utils`,
`base-lib/home-manager`, and `base-lib/opencode`; the top-level aggregator and
host flakes may still override those follows back to their own rooted graph.

Host inputs that are intentionally shared by multiple hosts should also be rooted
once in the top-level aggregator and followed from each path flake. Current shared
examples include `nixos-hardware`, `disko`, and the pinned Hyprland desktop inputs
used by both `tater` and `thorny` (`hyprland`, `Hyprspace`, `hypridle`, `anyrun`,
and `pip-chrome-extension`). Root shared package inputs such as `ctx` the same
way when multiple hosts consume them directly. For Hyprland ecosystem flakes that
use `nix-systems/default-linux`, also root a shared `systems` input and make each
consumer follow it. This keeps standalone host flakes usable while avoiding
duplicate transitive lock graphs in the root flake.

One intentional exception is `suremac/helix`: it keeps Helix's own `nixpkgs` so
the cached upstream Helix runtime can be fetched from `helix.cachix.org` instead
of building Darwin grammars locally. The Home Manager module trims that runtime
in the final profile closure.

After changing input topology, run `nix flake lock` and sanity-check the lock for
duplicate local graphs. Large repeated groups of `base-lib_*`, `hm-modules_*`,
`nixos-modules_*`, `home-manager_*`, or `opencode_*` nodes usually mean a new path
input is not following the root graph.

After input updates, remove stale overrides when Nix warns that an upstream input
no longer exists. Keep any still-valid nested overrides; for example, `rdny`
currently exposes `fleet` but no longer exposes a direct `srht` input, so only
`rdny.inputs.fleet.inputs.srht` should follow the shared root.

The root development shells are split so everyday checks do not require IDE and
Rust toolchain closures:

```bash
nix develop        # lean lint/deploy/update helper shell
nix develop .#rust # default tools plus cargo/rustc/rustfmt/clippy/pkg-config/OpenSSL
nix develop .#ide  # rust shell plus nil, nixd, bash-language-server, rust-analyzer
```

Keep heavyweight language servers and compile toolchains out of
`devShells.default` unless they are needed for normal repository checks.

For runtime closure work on Darwin, check for build-only toolchain retention with:

```bash
nix path-info --closure-size --human-readable .#darwinConfigurations.suremac.system
nix why-depends .#darwinConfigurations.suremac.system /nix/store/...-clang-wrapper-...
```

Prefer smaller runtime variants when behavior allows. For example, the shared
Home Manager Git module and shared NixOS system package set default to
`pkgs.gitMinimal`, because the full Darwin `git` package can retain Python and
the Darwin compiler/SDK toolchain while the minimal package covers normal CLI,
fetch/clone, signing, and jj interoperability workflows.

For NixOS hosts, start with:

```bash
nix path-info --closure-size --human-readable .#nixosConfigurations.<host>.config.system.build.toplevel
nix path-info -rS .#nixosConfigurations.<host>.config.system.build.toplevel
nix why-depends .#nixosConfigurations.<host>.config.system.build.toplevel /nix/store/...-suspect-package
```

When checking Linux systems from Darwin, these commands can only report complete
runtime closure sizes for paths that are already realised or substitutable from a
configured cache. If Nix reports that required `x86_64-linux` or `aarch64-linux`
builds are unavailable locally, run the same inspection on a Linux host or remote
builder such as `thorny`.

Warnings from upstream flakes that copy their source to the store again are eval
hygiene issues, not automatically runtime closure issues. Fix owned projects by
using the `self` flake input or `builtins.path { path = ./.; name = "source"; }`
instead of raw `./.` package sources. For fast-moving third-party flakes such as
Hyprland ecosystem inputs, prefer upstream PRs and only carry a local patch when
measurement shows the source copy is a significant evaluation bottleneck.

## Common closure bloat sources

Several NixOS defaults and nixpkgs packaging choices can silently inflate host
closures by hundreds of MB or more. Check for these when a host closure seems
unexpectedly large:

- **`services.speechd`** (text-to-speech): NixOS's `graphical-desktop.nix`
  module, imported by `programs.hyprland.enable`, enables `services.speechd`
  by default for accessibility. This pulls in `mbrola-voices` (~644 MB),
  `espeak-ng`, and `flite` as speech synthesis engines. Disable with
  `services.speechd.enable = false` unless a screen reader is actually needed.
  The `hyprland-desktop` NixOS module disables this by default.

- **Duplicate Hyprland builds**: When using a pinned flake-input Hyprland for
  the compositor, nixpkgs packages that depend on `pkgs.hyprland` (such as
  `grimblast` and `xdg-desktop-portal-hyprland`) pull in a second, separate
  Hyprland build. Override these packages via a host overlay to point at the
  same flake-input Hyprland:
  ```nix
  nixpkgs.overlays = [
    (final: prev: {
      grimblast = prev.grimblast.override { hyprland = hyprlandPackage; };
      xdg-desktop-portal-hyprland =
        prev.xdg-desktop-portal-hyprland.override { hyprland = hyprlandPackage; };
    })
  ];
  ```

- **Flake-input portal GCC leak**: The `xdg-desktop-portal-hyprland` from the
  Hyprland flake input (v1.3.11) leaks a runtime reference to the full
  `gcc-15.2.0` (~265 MB). Prefer the nixpkgs portal (`pkgs.xdg-desktop-portal-hyprland`,
  v1.3.12) which does not have this leak, and override its `hyprland` argument
  to the flake-input Hyprland as shown above.

- **`yt-dlp` / `deno` via `mpv`**: The default `mpv` package (`mpv-with-scripts`)
  enables `youtubeSupport = true`, which adds `yt-dlp` to the wrapper PATH.
  The nixpkgs `yt-dlp` package depends on `deno` (~136 MB) for its JavaScript
  extractor engine. Override with `mpv.override { youtubeSupport = false; }`
  if direct URL playback in mpv is not needed.

- **Heavy cursor/icon themes**: `bibata-cursors` is ~322 MB. Prefer lighter
  alternatives such as `capitaine-cursors` (~4 MB). The theming module defaults
  to `capitaine-cursors`.

- **`nix.registry.nixpkgs.flake`**: Pinning the nixpkgs flake in the registry
  (for `nix run nixpkgs#...` version matching) includes the full nixpkgs source
  tree (~199 MB) in the closure. This is a deliberate tradeoff; keep it if the
  version-pinned `nix run nixpkgs#...` workflow is used regularly.

- **Duplicate Python/systemd builds**: Some nixpkgs packages (e.g. `gstreamer`,
  `libcanberra`) depend on differently-configured Python or systemd derivations
  that are not shared with the system's main build. These are nixpkgs-internal
  issues that are hard to fix from the dotfiles config without patching upstream
  package definitions.

## Import-from-derivation policy

Do not add evaluation-time fetch/import workarounds in overlays or modules. In
particular, avoid `import (fetchFromGitHub ...)`, `import (fetchTarball ...)`, or
similar patterns that require Nix to realise a derivation while evaluating the
system graph. Host `drvPath` evaluation for active systems should keep working
with:

```bash
nix eval .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath \
  --raw \
  --no-write-lock-file \
  --option allow-import-from-derivation false \
  --option eval-cache false
```

When an upstream package regression needs a temporary fix, prefer this order:

1. Remove the workaround when the pinned nixpkgs already contains the upstream
   fix.
1. Carry the smallest local non-IFD overlay or patch against the current package
   set.
1. Only if a local patch is too invasive, add an explicit pinned flake input and
   document why the additional lock graph is justified.

SourceHut #116 removed the Cantarell workaround from
`flakes/base-lib/overlays/default.nix` because the pinned nixpkgs revision
`d407951447dcd00442e97087bf374aad70c04cea` already includes the fix for
NixOS/nixpkgs #535887 via `python3Packages.afdko` patch
`0002-otfautohint-fix-assertion-high-ghost-first-stem.patch`. Cantarell now uses
the normal pinned package set instead of importing a fetched historical nixpkgs
during evaluation.
