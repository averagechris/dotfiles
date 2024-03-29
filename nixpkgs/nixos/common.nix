{
  config,
  pkgs,
  lib,
  inputs,
  overlays,
  nixpkgs,
  ...
}: {
  nixpkgs.overlays = overlays;
  nix = {
    package = pkgs.nixFlakes;
    settings.substituters = [
      "https://cache.nixos.org/"
      "https://nix-community.cachix.org"
      "https://averagechris-dotfiles.cachix.org"
      "https://nixpkgs-wayland.cachix.org"
    ];
    settings.trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
      "averagechris-dotfiles.cachix.org-1:VwJkl5dG1+xGDY5x884mH/kVwwpgwBAdBKIF3BZiia4="
    ];
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
    trustedUsers = ["@wheel"];
  };

  nixpkgs.config.allowUnfree = true;

  # Select internationalization properties.
  i18n.defaultLocale = "en_US.UTF-8";

  environment.systemPackages = with pkgs; [
    git
    nix-index
    nix-prefetch-scripts
    neovim
    which
  ];
}
