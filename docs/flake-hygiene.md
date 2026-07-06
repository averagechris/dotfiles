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

Host inputs that are intentionally shared by multiple hosts should also be rooted
once in the top-level aggregator and followed from each path flake. Current shared
examples include `nixos-hardware`, `disko`, and the pinned Hyprland desktop inputs
used by both `tater` and `thorny` (`hyprland`, `Hyprspace`, `hypridle`, `anyrun`,
and `pip-chrome-extension`). This keeps standalone host flakes usable while
avoiding duplicate transitive lock graphs in the root flake.

One intentional exception is `suremac/helix`: it keeps Helix's own `nixpkgs` so
the cached upstream Helix runtime can be fetched from `helix.cachix.org` instead
of building Darwin grammars locally. The Home Manager module trims that runtime
in the final profile closure.

After changing input topology, run `nix flake lock` and sanity-check the lock for
duplicate local graphs. Large repeated groups of `base-lib_*`, `hm-modules_*`,
`nixos-modules_*`, `home-manager_*`, or `opencode_*` nodes usually mean a new path
input is not following the root graph.

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
