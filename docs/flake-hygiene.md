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
import it. If a host also pins a package flake that is already exposed by
`hm-modules` (for example `starship-jj`, `linear-cli`, or `gander`), make the
host input follow the `hm-modules/...` input so the root lock keeps one node.

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
Home Manager Git module defaults to `pkgs.gitMinimal`, because the full Darwin
`git` package can retain Python and the Darwin compiler/SDK toolchain while the
minimal package covers normal CLI, signing, and jj interoperability workflows.
