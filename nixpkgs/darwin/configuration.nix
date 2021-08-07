{ config, pkgs, ... }:
{
  imports = [ <home-manager/nix-darwin> ./local_config.nix];

  # Use a custom configuration.nix location.
  # $ darwin-rebuild switch -I darwin-config=$HOME/.config/nixpkgs/darwin/configuration.nix
  environment.darwinConfig = "$HOME/.config/nixpkgs/darwin/configuration.nix";

  home-manager.useUserPackages = true;
  home-manager.useGlobalPkgs = true;

  system.defaults.dock.autohide = true;
  system.defaults.dock.mru-spaces = false;
  system.defaults.dock.orientation = "left";
  system.defaults.dock.showhidden = true;

  services.yabai.enable = true;
  services.yabai.package = pkgs.yabai;
  services.skhd.enable = true;
  services.skhd.package = pkgs.skhd;
  # services.emacs.enable = true;
  # services.emacs.package = config.home-manager.users.christophercummings.programs.emacs.package;

  programs.zsh.enable = true;

  # enable launchd daemon for mbsync to sync and index emails if emails are configured in home-manager config
  launchd.user.agents.mbsync = if config.home-manager.users.christophercummings.accounts.email.accounts != {} then {
    command = "${pkgs.isync}/bin/mbsync -a && mu ${pkgs.mu}/bin/mu index";
    serviceConfig.StartInterval = 60 * 5;
  } else {};
}
