{ pkgs, ... }:

let
  doom-emacs = pkgs.callPackage (builtins.fetchTarball {
    url = https://github.com/vlaci/nix-doom-emacs/archive/master.tar.gz;
  })
  {
    doomPrivateDir = ./doom.d;
  };

in {
  programs.emacs.extraPackages = epkgs: [ epkgs.emacs-libvterm ];
  home.packages = with pkgs; [
    doom-emacs

    (aspellWithDicts (dicts: with dicts; [ en en-computers en-science ]))
    ripgrep
    shellcheck
  ];
  home.file.".emacs.d/init.el".text = ''
    (load "default.el")
  '';
}
