{
  description = "Darwin modules for nix-darwin configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    base-lib = {
      url = "path:../base-lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {...}: {
    darwinModules = {
      configuration = ./modules/configuration.nix;
      desktop = ./modules/desktop.nix;
      karabiner = ./modules/karabiner.nix;
      skhd = ./modules/skhd.nix;
    };
  };
}
