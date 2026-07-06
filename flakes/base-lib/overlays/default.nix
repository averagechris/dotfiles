# Empty overlay - titlecase is now handled directly in mkNixosHost/mkDarwinHost
{
  inputs,
  nixpkgs,
  titlecase,
  opencode ? null,
}: {
  default = final: prev: {
    opencode =
      if opencode != null && builtins.hasAttr prev.stdenv.hostPlatform.system opencode.packages
      then let
        inherit (prev.stdenv.hostPlatform) system;
        rev = opencode.shortRev or opencode.dirtyShortRev or "dirty";
        upstreamHashes = builtins.fromJSON (builtins.readFile "${opencode}/nix/hashes.json");
        nodeModulesOverrides = {
          # Upstream dev changed transitive dependency output without updating
          # nix/hashes.json for this revision. Keep this scoped to the exact
          # revision so future upstream hash updates are used automatically.
          "3b7a5e783d59e8986dca6e5df48663613fa80722" = {
            hash.aarch64-darwin = "sha256-81IAmdjiYZz8IgMJt0+VxzdOS80gTHc5SendwEW/vD4=";
          };

          # Upstream updated package.json to reference a newer ghostty-web
          # revision but left bun.lock pinned to the previous commit. Patch the
          # lockfile until the upstream flake catches up.
          "0f272d931d806681a0f7f19538e2f3f1d52d1832" = {
            hash.aarch64-darwin = "sha256-+lx7mv1QM+nl3UPY9GxPcbWlhK4TKYp96rvJd51Exig=";
            postPatch = ''
              substituteInPlace bun.lock \
                --replace-fail '"ghostty-web": ["ghostty-web@github:anomalyco/ghostty-web#20bd361", {}, "anomalyco-ghostty-web-20bd361", "sha512-dW0nwaiBBcun9y5WJSvm3HxDLe5o9V0xLCndQvWonRVubU8CS1PHxZpLffyPt1YujPWC13ez03aWxcuKBPYYGQ=="]' \
                               '"ghostty-web": ["ghostty-web@github:anomalyco/ghostty-web#513463a", {}, "anomalyco-ghostty-web-513463a", "sha512-GZR8LSmgGzViWnBJrqRI8MpAZRCJxhcr1Hi9Tyeh7YRooHZQjK9J97FQRD3tbBaM2wjq05gzGY2UEsG+JtZeBw=="]'
            '';
          };
        };
        override = nodeModulesOverrides.${opencode.rev or ""} or {};
        hasSystemOverride = builtins.hasAttr system (override.hash or {});
        node_modules =
          (final.callPackage "${opencode}/nix/node_modules.nix" {
            inherit rev;
            hash =
              (override.hash or {}).${system} or upstreamHashes.nodeModules.${system};
          }).overrideAttrs (old: {
            postPatch = (old.postPatch or "") + (final.lib.optionalString hasSystemOverride (override.postPatch or ""));
          });
      in
        final.callPackage "${opencode}/nix/opencode.nix" {
          inherit node_modules;
        }
      else prev.opencode;

    # Temporary workaround for https://github.com/NixOS/nixpkgs/issues/535887
    # cantarell-fonts 0.311 fails to build with afdko 5.0.1; use afdko 4.0.2
    # from the revision just before the 5.0.1 bump, disabling tests because
    # they fail against current dependencies.
    cantarell-fonts = let
      nixpkgs-afdko4 =
        import (final.fetchFromGitHub {
          owner = "NixOS";
          repo = "nixpkgs";
          rev = "a95fcb976497422a1df26883b7d3907470c55543";
          sha256 = "00mbdjs7yhym1f7qj4vagvxyp0fxxdcg1hxwf1cqkaz79pwyvg83";
        }) {
          system = final.stdenv.hostPlatform.system;
          inherit (final) config;
          overlays = [
            (self: super: {
              python3 = super.python3.override {
                packageOverrides = pyself: pysuper: {
                  afdko = pysuper.afdko.overridePythonAttrs (_: {
                    doCheck = false;
                    dontUsePytestCheck = true;
                  });
                };
              };
            })
          ];
        };
    in
      prev.cantarell-fonts.override {
        inherit (nixpkgs-afdko4) python3;
      };

    pi-coding-agent = final.callPackage ../packages/pi-coding-agent.nix {};
    pi = final.pi-coding-agent;
    coderabbit-cli = final.callPackage ../packages/coderabbit-cli.nix {};
    helium-bin = final.callPackage ../packages/helium-bin.nix {};
    notion-cli = final.callPackage ../packages/notion-cli.nix {};
    pup = final.callPackage ../packages/pup.nix {};
    rodney = final.callPackage ../packages/rodney.nix {};
    sentry = final.callPackage ../packages/sentry.nix {};
    showboat = final.callPackage ../packages/showboat.nix {};
  };
}
