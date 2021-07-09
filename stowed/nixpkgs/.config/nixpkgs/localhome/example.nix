##################################################
##################################################
##################################################
##################################################
#
# use this as an example for localhome/default.nix
#
##################################################
##################################################
##################################################
##################################################
##################################################

{ config, pgks, ... }:

{
  # import whatever modules you want on this system
  imports = [
    ../emacs
    ../email
    ../firefox
    ../guiapps
    ../mycli
    ../neovim
    ../pgcli
    ../python
    ../rust
    ../shell
    ../skhd
    ../tmux
    ../yabai
  ];

  home.username = "your_user_name";
  home.homeDirectory = "/home/chris";
  home.stateVersion = "21.05";
  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    userName = "My full name";
    userEmail = "email@email.com";
    extraConfig = { pull.rebase = true; };
  };


  # probably don't need any of the below on macos
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

  # allows Gnome to find the gui applications
  targets.genericLinux.enable = true;
  xdg.enable = true;
  xdg.mime.enable = true;

  # make sure all of the distro's default XDG_DATA_DIRS values are in here
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
