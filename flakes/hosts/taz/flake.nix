{
  description = "Taz NixOS system configuration";

  inputs = {
    base-lib = {
      url = "path:../../base-lib";
    };
    nixos-modules = {
      url = "path:../../nixos-modules";
    };
    hm-modules = {
      url = "path:../../hm-modules";
    };
    nixpkgs = {
      follows = "base-lib/nixpkgs";
    };
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware/master";
    };
    home-manager = {
      follows = "base-lib/home-manager";
    };
    flake-utils = {
      follows = "base-lib/flake-utils";
    };
    agenix = {
      follows = "base-lib/agenix";
    };
    deploy-rs = {
      follows = "base-lib/deploy-rs";
    };
    helix = {
      url = "github:helix-editor/helix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    starship-jj = {
      url = "sourcehut:~averagechris/starship-jj";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    titlecase = {
      follows = "base-lib/titlecase";
    };
  };

  outputs = inputs @ {
    self,
    base-lib,
    nixpkgs,
    home-manager,
    ...
  }: let
    system = "x86_64-linux";
    inherit (base-lib) lib;
    # Create a custom specialArgs that includes our modules
    customSpecialArgs = system: let
      baseSpecialArgs = lib.specialArgs system;
    in
      baseSpecialArgs
      // {
        inherit inputs;
        # Fix overlays to be a set of overlay functions instead of a function
        overlays = {
          default = final: prev: {};
        };
      };
    # Create a custom mkHost that uses our specialArgs
    mkHostWithModules = hostPath: let
      specialArgs = customSpecialArgs system;
      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
        };
        overlays = [
          (final: prev: {
            titlecase = inputs.titlecase.packages.${system}.default;
          })
        ];
      };
    in
      nixpkgs.lib.nixosSystem {
        inherit pkgs system specialArgs;
        modules = [
          hostPath
          home-manager.nixosModules.home-manager
          {
            home-manager.extraSpecialArgs = specialArgs;
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "hm.bak";
          }
        ];
      };
  in {
    nixosConfigurations.taz = mkHostWithModules ./configuration.nix;

    deploy.nodes.taz = lib.mkDeploy' self.nixosConfigurations.taz;
  };
}
