{ pkgs }:

let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  # NOTE: won't need to overrideAttrs on emacsMacport once the below PR is released
  # https://github.com/NixOS/nixpkgs/pull/133260/
  pkg-emacs = if isLinux then pkgs.emacs else
  pkgs.emacsMacport.overrideAttrs (old: {
    passthru = old.passthru or { };
  });
in
pkgs.callPackage
  (builtins.fetchTarball {
    url = "https://github.com/vlaci/nix-doom-emacs/archive/master.tar.gz";
  })
{
  dependencyOverrides = {
    "emacs-overlay" = (builtins.fetchTarball {
      url = https://github.com/nix-community/emacs-overlay/archive/master.tar.gz;
    });
  };
  emacsPackagesOverlay = self: super: {
    # https://github.com/vlaci/nix-doom-emacs/issues/394
    # package was renamed 😎
    gitignore-mode = pkgs.emacsPackages.git-modes;
    gitconfig-mode = pkgs.emacsPackages.git-modes;
  };
  doomPrivateDir = ./doom.d;
  extraConfig = ''
    (setq
        mu4e-mu-binary "${pkgs.mu}/bin/mu"
        sendmail-program "${pkgs.msmtp}/bin/msmtp"
        message-sendmail-f-is-evil t
        message-sendmail-extra-arguments '("--read-envelope-from")
        message-send-mail-function 'message-send-mail-with-sendmail)
  '';
  extraPackages = epkgs: [ pkgs.emacs-all-the-icons-fonts pkgs.mu epkgs.vterm ];
  emacsPackages = pkgs.emacsPackagesFor pkg-emacs;
}
