{ config, pgks, ... }:

{
  imports = [
    ../emacs
    ../email
    ../firefox
    ../guiapps
    ../neovim
    ../python
    ../rust
    ../shell
    ../tmux
  ];

  home.username = "chris";
  home.homeDirectory = "/home/chris";
  home.stateVersion = "21.05";
  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    userName = "Chris Cummings";
    userEmail = "chris@thesogu.com";
    extraConfig = { pull.rebase = true; };
  };

  home.sessionVariables = {
    BROSWER = "firefox";
  };

  pam.sessionVariables = config.home.sessionVariables // {
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

  targets.genericLinux.enable = true;
  xdg.enable = true;
  xdg.mime.enable = true;
  xdg.systemDirs.data = [
    "/usr/share/pop"
    "/home/chris/.local/share/flatpak/exports/share"
    "/var/lib/flatpak/exports/share"
    "/usr/local/share"
    "/usr/share"
    "/home/chris/.nix-profile/share"
    "/home/chris/.nix-profile/share/applications"
  ];
}
