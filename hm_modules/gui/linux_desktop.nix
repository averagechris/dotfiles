{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.gui;
  inherit (pkgs.stdenv.hostPlatform) isLinux;
in
  with lib; {
    config = mkIf (cfg.enable && isLinux) {
      pam.sessionVariables = {
        LANGUAGE = "en_US:en";
        LANG = "en_US.UTF-8";
        LC_NUMERIC = "en_US.UTF-8";
        LC_TIME = "en_US.UTF-8";
        LC_MONETARY = "en_US.UTF-8";
        LC_PAPER = "en_US.UTF-8";
        LC_NAME = "en_US.UTF-8";
        LC_ADDRESS = "en_US.UTF-8";
        LC_TELEPHONE = "en_US.UTF-8";
        LC_MEASUREMENT = "en_US.UTF-8";
        LC_IDENTIFICATION = "en_US.UTF-8";
        PAPERSIZE = "letter";
      };

      targets.genericLinux.enable = mkDefault false;
      xdg.enable = mkDefault true;
      xdg.mime.enable = mkDefault true;

      # make sure all of the distro's default XDG_DATA_DIRS values are in here
      xdg.systemDirs.data = [
        "${config.home.homeDirectory}/.nix-profile/share"
        "${config.home.homeDirectory}/.nix-profile/share/applications"
      ];
    };
  }
