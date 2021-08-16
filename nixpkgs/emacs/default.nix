{ pkgs, config, ... }:

let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  doom = (import ./doom.nix { pkgs = pkgs; });

  pkgs-markdownMode = with pkgs; [
    mdl
    pandoc
    proselint
    python39Packages.grip
  ];

  pkgs-pythonMode = with pkgs.python39Packages; [
    black
    isort
    pkgs.poetry
    pyflakes
    pkgs.nodePackages.pyright
  ];

  pkgs-shellMode = with pkgs; [
    shellcheck
  ];

  pkgs-misc = with pkgs; [
    (aspellWithDicts (dicts: with dicts; [ en en-computers en-science ]))
    direnv
    fd
    ripgrep
    sqlite
    wordnet
  ];

  pkgs-linux = with pkgs; if isLinux then [
    # these are needed to support doom :tool everywhere (emacs-everywhere)
    xclip
    xdotool
    xorg.xprop
    xorg.xwininfo
  ] else [];

in
{
  config.home.packages = [ doom ] ++ pkgs-markdownMode ++ pkgs-pythonMode ++ pkgs-shellMode ++ pkgs-misc ++ pkgs-linux;

  config.home.file.".emacs.d/init.el".text = ''
    (load "default.el")
  '';

  # on macos nix-darwin handles the service configuration
  config.services =
    if isLinux then {
      emacs.enable = isLinux;
      emacs.package = doom;
      lorri.enable = isLinux;
    } else { };

}
