{
  description = "Trainwreck NixOS system configuration - Hetzner VPS";

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
    home-manager.follows = "base-lib/home-manager";
    flake-utils.follows = "base-lib/flake-utils";
    agenix.follows = "base-lib/agenix";
    deploy-rs.follows = "base-lib/deploy-rs";
    titlecase.follows = "base-lib/titlecase";

    # Disko for declarative disk partitioning
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # starship-jj for jujutsu starship prompt integration
    starship-jj.follows = "hm-modules/starship-jj";
  };

  outputs = inputs @ {
    self,
    base-lib,
    ...
  }: let
    system = "aarch64-linux";
    inherit (base-lib) lib;
  in {
    nixosConfigurations.trainwreck = lib.mkNixosHost {
      inherit system;
      hostPath = ./configuration.nix;
      extraInputs = inputs;
    };

    deploy.nodes.trainwreck = lib.mkDeploy self.nixosConfigurations.trainwreck;
  };
}
