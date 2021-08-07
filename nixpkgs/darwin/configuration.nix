{ config, pkgs, ... }:

{
  imports = [ <home-manager/nix-darwin> ];

  # Use a custom configuration.nix location.
  # $ darwin-rebuild switch -I darwin-config=$HOME/.config/nixpkgs/darwin/configuration.nix
  environment.darwinConfig = "$HOME/.config/nixpkgs/darwin/configuration.nix";

  home-manager.users.christophercummings = { pkgs, ... }: {
    imports = [ ../nixpkgs/home.nix ];
  };

  system.defaults.dock.autohide = true;
  system.defaults.dock.mru-spaces = false;
  system.defaults.dock.orientation = "left";
  system.defaults.dock.showhidden = true;

  services.yabai.enable = true;
  # services.yabai.package = pkgs.yabai;
  services.skhd.enable = true;
  # services.skhd.package = pkgs.skhd;

  # launchd.user.agents.syncemail = {
  #   command = "${pkgs.isync}/bin/mbsync -a && mu ${pkgs.mu}/bin/mu index";
  #   serviceConfig.StartInterval = 60 * 5;
  # };

}
