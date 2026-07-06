{
  description = "Base library for dotfiles - shared functions and utilities";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    titlecase = {
      url = "sourcehut:~averagechris/titlecase";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    opencode = {
      url = "github:anomalyco/opencode";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    nixpkgs,
    flake-utils,
    home-manager,
    darwin,
    deploy-rs,
    agenix,
    titlecase,
    ...
  }: let
    # Import SSH keys
    sshKeys = import ./ssh-keys/default.nix;

    # Import library functions
    lib = import ./lib/default.nix {
      inherit inputs nixpkgs flake-utils home-manager darwin deploy-rs agenix titlecase sshKeys;
    };

    # Import overlays
    overlaysModule = import ./overlays/default.nix {
      inherit inputs nixpkgs titlecase;
      opencode = inputs.opencode or null;
    };
  in {
    # Export library functions
    lib = {
      inherit (lib) mkHost mkNixosHost mkDarwinHost mkDeploy mkDeploy' mkSpecialArgs specialArgs dotfiles_lib mkHyprlandConfigCheck mergeFlakeChecks;
    };

    # Export SSH keys
    inherit sshKeys;

    # Export overlays as a function that takes system
    overlays.default = overlaysModule.default;
  };
}
