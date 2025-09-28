{
  inputs,
  lib,
  overlays,
  pkgs,
  ...
}: {
  imports = [./openssh-client.nix];
  nixpkgs.overlays = lib.attrValues overlays;
  nix = {
    gc.automatic = true;
    gc.dates = "daily";
    gc.options = "--delete-older-than 14d";
    registry.nixpkgs.flake = inputs.nixpkgs; # makes nix run nixpkgs#... faster
    settings.substituters = [
      "https://cache.nixos.org/"
      "https://nix-community.cachix.org"
      "https://averagechris-dotfiles.cachix.org"
      "https://nixpkgs-wayland.cachix.org"
      "https://devenv.cachix.org"
      "https://helix.cachix.org"
    ];
    settings = {
      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
        "averagechris-dotfiles.cachix.org-1:VwJkl5dG1+xGDY5x884mH/kVwwpgwBAdBKIF3BZiia4="
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
        "helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs="
      ];
      trusted-users = ["@wheel"];
    };
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

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
