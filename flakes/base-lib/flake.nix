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
    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mac-app-util.url = "github:hraban/mac-app-util";
    titlecase = {
      url = "sourcehut:~averagechris/titlecase";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    nixpkgs,
    flake-utils,
    home-manager,
    darwin,
    deploy-rs,
    pre-commit-hooks,
    agenix,
    mac-app-util,
    titlecase,
    ...
  }: let
    # Import SSH keys
    sshKeys = import ./ssh-keys/default.nix;

    # Import library functions
    lib = import ./lib/default.nix {
      inherit inputs nixpkgs flake-utils home-manager darwin deploy-rs pre-commit-hooks agenix mac-app-util titlecase sshKeys;
    };

    # Import overlays
    overlaysModule = import ./overlays/default.nix {
      inherit inputs nixpkgs titlecase;
    };
  in
    {
      # Export library functions
      lib = {
        inherit (lib) mkHost mkNixosHost mkDarwinHost mkDeploy mkDeploy' mkCommitCheck mkSpecialArgs specialArgs dotfiles_lib;
      };

      # Export SSH keys
      inherit sshKeys;

      # Export overlays as a function that takes system
      overlays.default = overlaysModule.default;
    }
    // flake-utils.lib.eachDefaultSystem (system: {
      checks = lib.mkCommitCheck system;
    });
}
