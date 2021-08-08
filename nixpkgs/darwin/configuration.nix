{ config, pkgs, ... }:
{
  imports = [ <home-manager/nix-darwin> ./local_config.nix ];

  # Use a custom configuration.nix location.
  # $ darwin-rebuild switch -I darwin-config=$HOME/.config/nixpkgs/darwin/configuration.nix
  environment.darwinConfig = "$HOME/.config/nixpkgs/darwin/configuration.nix";

  home-manager.useUserPackages = true;
  home-manager.useGlobalPkgs = true;

  services.nix-daemon.enable = true;
  nix.package = pkgs.nix;

  # TODO FIXME these are not working right now
  # temporarily installing w/ homebrew
  # services.yabai.enable = true;
  # services.yabai.package = pkgs.yabai;
  # services.skhd.enable = true;
  # services.skhd.package = pkgs.skhd;

  # services.emacs.enable = true;
  # TODO FIXME not sure how to pass the doom-emacs package to this variable
  # services.emacs.package = config.home-manager.users.christophercummings.services.emacs.package;

  # makes nix-darwin put handling in /etc/static/zsh* files so that NIX_PATH correctly
  # references all of the nix-darwin stuff
  # does not conflict with home-manager.programs.zsh
  programs.zsh.enable = true;

  # enable launchd daemon for mbsync to sync and index emails if emails are configured in home-manager config
  launchd.user.agents.mbsync =
    if config.home-manager.users.christophercummings.accounts.email.accounts != { } then {
      command = "${pkgs.isync}/bin/mbsync -a && mu ${pkgs.mu}/bin/mu index";
      serviceConfig.StartInterval = 60 * 5;
    } else { };

  system.defaults.NSGlobalDomain.AppleKeyboardUIMode = 3;
  system.defaults.NSGlobalDomain.NSAutomaticCapitalizationEnabled = false;
  system.defaults.NSGlobalDomain.NSAutomaticDashSubstitutionEnabled = false;
  system.defaults.NSGlobalDomain.NSAutomaticPeriodSubstitutionEnabled = false;
  system.defaults.NSGlobalDomain.NSAutomaticQuoteSubstitutionEnabled = false;
  system.defaults.NSGlobalDomain.NSAutomaticSpellingCorrectionEnabled = false;
  system.defaults.NSGlobalDomain.NSNavPanelExpandedStateForSaveMode = true;
  system.defaults.NSGlobalDomain.NSNavPanelExpandedStateForSaveMode2 = true;
  system.defaults.NSGlobalDomain._HIHideMenuBar = true;

  system.defaults.finder.AppleShowAllExtensions = true;
  system.defaults.finder.FXEnableExtensionChangeWarning = false;

  system.defaults.dock.autohide = true;
  system.defaults.dock.mru-spaces = false;
  system.defaults.dock.orientation = "left";
  system.defaults.dock.showhidden = true;

  system.defaults.trackpad.Clicking = true;
  system.defaults.trackpad.TrackpadThreeFingerDrag = true;

  system.keyboard.enableKeyMapping = false;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;
}
