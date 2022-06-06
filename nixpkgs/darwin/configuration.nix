{
  config,
  pkgs,
  ...
}: let
  pii = import ./pii.nix;
in {
  imports = [
    <home-manager/nix-darwin>

    ./desktop.nix
    ./skhd.nix
    ./yabai.nix
  ];

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;

  # Use a custom configuration.nix location.
  # $ darwin-rebuild switch -I darwin-config=$HOME/.config/nixpkgs/darwin/configuration.nix
  environment.darwinConfig = "$HOME/.config/nixpkgs/darwin/configuration.nix";
  services.nix-daemon.enable = true;
  nix.package = pkgs.nix;

  users.users."${pii.userName}" = {
    name = "${pii.userName}";
    home = "${pii.homeDirectory}";
  };

  home-manager.useUserPackages = true;
  home-manager.useGlobalPkgs = true;
  home-manager.users."${pii.userName}" = {pkgs, ...}: {
    imports = [../home.nix];
  };

  # makes nix-darwin put handling in /etc/static/zsh* files so that NIX_PATH correctly
  # references all of the nix-darwin stuff
  # does not conflict with home-manager.programs.zsh
  programs.zsh.enable = true;

  # services.emacs.enable = true;
  # TODO FIXME not sure how to pass the doom-emacs package to this variable
  # services.emacs.package = config.home-manager.users."${pii.userName}".services.emacs.package;

  # enable launchd daemon for mbsync to sync and index emails if emails are configured in home-manager config
  launchd.user.agents.mbsync =
    if config.home-manager.users."${pii.userName}".accounts.email.accounts != {}
    then {
      command = "${pkgs.isync}/bin/mbsync -a && mu ${pkgs.mu}/bin/mu index";
      serviceConfig.StartInterval = 60 * 5;
    }
    else {};

  services.lorri.enable = true;
}
