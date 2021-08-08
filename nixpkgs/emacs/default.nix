{ pkgs, ... }:

let
  # TODO inquire / fix upstream emacsMacport currently breaks due to a missing attribute: `passthru`
  emacs-pkg = pkgs.emacs;
    # if pkgs.stdenv.hostPlatform.isLinux then pkgs.emacs else pkgs.emacsMacport;
  doom-emacs = pkgs.callPackage
    (builtins.fetchTarball {
      url = "https://github.com/vlaci/nix-doom-emacs/archive/master.tar.gz";
    })
    {
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
      emacsPackages = pkgs.emacsPackagesFor emacs-pkg;
    };

in
{
  home.packages = with pkgs; [
    doom-emacs

    (aspellWithDicts (dicts: with dicts; [ en en-computers en-science ]))

    direnv
    fd
    nixfmt
    pandoc
    ripgrep
    shellcheck
    nodePackages.pyright
  ];
  home.file.".emacs.d/init.el".text = ''
    (load "default.el")
  '';

  services.emacs = {
    # on macos nix-darwin handles the service configuration
    enable = pkgs.stdenv.hostPlatform.isLinux;
    package = doom-emacs;
  };

}