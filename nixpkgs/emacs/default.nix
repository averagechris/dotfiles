{ pkgs, config, ... }:

let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  doom = (import ./doom.nix { pkgs = pkgs; });

in
{
  config.home.packages = with pkgs; [
    (aspellWithDicts (dicts: with dicts; [ en en-computers en-science ]))

    direnv
    doom
    fd
    nixfmt
    pandoc
    ripgrep
    shellcheck
    nodePackages.pyright
  ];
  config.home.file.".emacs.d/init.el".text = ''
    (load "default.el")
  '';

  # on macos nix-darwin handles the service configuration
  config.services =
    if isLinux then {
      emacs.enable = isLinux;
      emacs.package = doom;
      lorri.enable = true;
    } else { };

}
