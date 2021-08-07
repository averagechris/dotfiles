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
  ###
  ### Tell home-manager the basicss
  ###
  config.home.username = "<username>";
  # on macos this is /Users/<username>
  config.home.homeDirectory = "/home/chris";

  ###
  ### Choose which modules to install on this system
  ###
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

  ###
  ### Setup the git personal info relevant for this system
  ###
  config.programs.git = {
    userName = ":)";
    userEmail = "email@email.com";
  };

  ###
  ### Enable specific email accounts
  ###
  config.accounts.email.accounts = {
    # add a new email account by adding a nix module, then adding it to the .gitignore
    # or ignore privately
    # see example-email.nix for an example
    # e.g.:
    # example = import ../email/example-email.nix;
    # personal = import ../email/personal.nix
  };

  ####
  #### extra options to consider
  ####

  # if on a machine using aws cli you probably want to set this
  # to the profile you use most often
  config.programs.zsh.sessionVariables = {
    AWS_PROFILE = "????";
  };

  # if on pop-os you probably want to add these
  # make sure all of the distro's default XDG_DATA_DIRS values are in here
  # most of these should be set in linux_desktop/default.nix
  config.xdg.systemDirs.data = [
    "/usr/share/pop"
    "/var/lib/flatpak/exports/share"
  ];
}
