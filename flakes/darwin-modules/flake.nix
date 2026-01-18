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
    # Note: Legacy modules archived in ./archive/
    # See archive/README.md for restoration instructions
    darwinModules = {};
  };
}
