# Empty overlay - titlecase is now handled directly in mkNixosHost/mkDarwinHost
{
  inputs,
  nixpkgs,
  titlecase,
  opencode ? null,
}: {
  default = final: prev: let
    linkWithLld = package:
      package.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or []) ++ [final.llvmPackages.lld];
        env =
          (old.env or {})
          // {
            NIX_CFLAGS_LINK = "-fuse-ld=lld";
          };
      });

    # cctools ld64 1010.6 traps while linking QtMacExtras and KeePassXC with
    # the current Darwin Clang 21 toolchain. Keep the workaround scoped to
    # KeePassXC and its otherwise-unshared Qt5 dependency.
    keepassxcQtMacExtras = linkWithLld prev.libsForQt5.qtmacextras;
  in {
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

    pi-coding-agent = final.callPackage ../packages/pi-coding-agent.nix {};
    pi = final.pi-coding-agent;
    helium-bin = final.callPackage ../packages/helium-bin.nix {};
    notion-cli = final.callPackage ../packages/notion-cli.nix {};
    pup = final.callPackage ../packages/pup.nix {};
    sentry = final.callPackage ../packages/sentry.nix {};
    showboat = final.callPackage ../packages/showboat.nix {};

    keepassxc =
      if prev.stdenv.hostPlatform.isDarwin
      then
        linkWithLld (
          prev.keepassxc.override {
            libsForQt5 =
              prev.libsForQt5
              // {qtmacextras = keepassxcQtMacExtras;};
          }
        )
      else prev.keepassxc;
  };
}
