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
  config.home.username = "your_user_name";
  config.home.homeDirectory = "/home/chris";

  # import whatever modules you want on this system
  imports = [
    ../emacs
    ../email
    ../firefox
    ../git
    ../guiapps
    ../linux_destop
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

  config.programs.git = {
    userName = ":)";
    userEmail = "email@email.com";
  };

  config.accounts.email.accounts = {
    # add a new email account by adding a nix module, then adding it to the .gitignore
    # or ignore privately
    # see example-email.nix for an example
    # e.g.:
    # example = import ../email/example-email.nix;
  };

  # make sure all of the distro's default XDG_DATA_DIRS values are in here
  # most of these should be set in linux_desktop/default.nix
  config.xdg.systemDirs.data = [
    "/usr/share/pop"
    "/var/lib/flatpak/exports/share"
  ];
}
