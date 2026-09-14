# Package overrides shared by all hosts. Titlecase is handled directly in
# mkNixosHost/mkDarwinHost instead of here.
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
        rev = opencode.shortRev or opencode.dirtyShortRev or "dirty";
        node_modules = final.callPackage "${opencode}/nix/node_modules.nix" {inherit rev;};
      in
        final.callPackage "${opencode}/nix/opencode.nix" {
          inherit node_modules;
        }
      else prev.opencode;

    pi-coding-agent = final.callPackage ../packages/pi-coding-agent.nix {};
    pi = final.pi-coding-agent;
    glaze-v7 = final.callPackage ../packages/glaze-v7.nix {};
    helium-bin = final.callPackage ../packages/helium-bin.nix {};
    notion-cli = final.callPackage ../packages/notion-cli.nix {};
    pup = final.callPackage ../packages/pup.nix {};
    sentry = final.callPackage ../packages/sentry.nix {};
    showboat = final.callPackage ../packages/showboat.nix {};
    rose-pine-gtk-modern = final.callPackage ../packages/rose-pine-gtk-modern.nix {};

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
