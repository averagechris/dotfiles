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

let
  userName = "chris";
  # on macos this is /Users/<username>
  homeDirectory = "/home/${userName}";
in
{
  ###
  ### Tell home-manager the basics
  ###
  config.home.username = userName;
  config.home.homeDirectory = homeDirectory;

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
    ../personal_scripts
    ../pgcli
    ../python
    ../rust
    ../shell
    ../window_manager
    ../terminal_emulator
    ../tmux

    # probably don't want these since they're macos only and are configured in darwin.skhd and darwin.yabai
    # ../skhd
    # ../yabai
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

  # if using sway window manager, make global display changes
  # here
  # but tweak display profiles in `window_managers/sway/kanshi.nix`
  # NOTE to see what sway knows about the available displays
  # run: `swaymsg -t get_outputs`
  config.wayland.windowManager.sway.config = {
    output."*".bg = "${homeDirectory}/wallpapers/1.jpg fill";
    startup = [ ];
  };

}
