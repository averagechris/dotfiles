{
  config,
  inputs,
  pkgs,
  ...
}: {
  imports = [
    inputs.home-manager.darwinModules.home-manager
  ];

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;

  services.nix-daemon.enable = true;
  nix.package = pkgs.nix;

  # makes nix-darwin put handling in /etc/static/zsh* files so that NIX_PATH correctly
  # references all of the nix-darwin stuff
  # does not conflict with home-manager.programs.zsh
  programs.zsh.enable = true;

  # enable launchd daemon for mbsync to sync and index emails if emails are configured in home-manager config
  services.lorri.enable = true;
}
