{
  description = "Tootsie NixOS system configuration";

  inputs = {
    base-lib.url = "path:../../base-lib";
    nixpkgs.follows = "base-lib/nixpkgs";
    nixos-modules = {
      url = "path:../../nixos-modules";
      inputs.base-lib.follows = "base-lib";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    hm-modules = {
      url = "path:../../hm-modules";
      inputs.base-lib.follows = "base-lib";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.home-manager.follows = "home-manager";
      inputs.opencode.follows = "base-lib/opencode";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager.follows = "base-lib/home-manager";
    flake-utils.follows = "base-lib/flake-utils";
    agenix.follows = "base-lib/agenix";
    deploy-rs.follows = "base-lib/deploy-rs";
    titlecase.follows = "base-lib/titlecase";
    helix.follows = "hm-modules/helix";
    starship-jj.follows = "hm-modules/starship-jj";
  };

  outputs = inputs @ {
    self,
    base-lib,
    ...
  }: let
    system = "x86_64-linux";
    inherit (base-lib) lib;
  in {
    nixosConfigurations.tootsie = lib.mkNixosHost {
      inherit system;
      hostPath = ./configuration.nix;
      extraInputs = inputs;
    };

    deploy.nodes.tootsie = lib.mkDeploy self.nixosConfigurations.tootsie;
  };
}
