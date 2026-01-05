{
  description = "Suremac Darwin system configuration";

  inputs = {
    base-lib = {
      url = "path:../../base-lib";
    };
    hm-modules = {
      url = "path:../../hm-modules";
    };
    darwin-modules = {
      url = "path:../../darwin-modules";
    };
    nixpkgs = {
      follows = "base-lib/nixpkgs";
    };
    darwin = {
      follows = "base-lib/darwin";
    };
    home-manager = {
      follows = "base-lib/home-manager";
    };
    flake-utils = {
      follows = "base-lib/flake-utils";
    };
    mac-app-util = {
      follows = "base-lib/mac-app-util";
    };
    agenix = {
      follows = "base-lib/agenix";
    };
    deploy-rs = {
      follows = "base-lib/deploy-rs";
    };
    titlecase = {
      follows = "base-lib/titlecase";
    };
    helix = {
      url = "github:helix-editor/helix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    starship-jj = {
      url = "sourcehut:~averagechris/starship-jj";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    base-lib,
    nixpkgs,
    darwin,
    home-manager,
    flake-utils,
    mac-app-util,
    ...
  }: let
    system = "aarch64-darwin";
    inherit (base-lib) lib;
    # Create a custom specialArgs that includes our modules
    customSpecialArgs = system:
      (lib.specialArgs system)
      // {
        inherit inputs;
      };
    # Create a custom mkHost that uses our specialArgs
    mkHostWithModules = hostPath: let
      isMacos = system == flake-utils.lib.system.aarch64-darwin;
      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          allowUnsupportedSystem = isMacos;
          allowBroken = isMacos;
        };
        overlays = [
          (final: prev: {
            titlecase = inputs.titlecase.packages.${system}.default;
          })
        ];
      };
      fn =
        if system == "aarch64-darwin"
        then darwin.lib.darwinSystem
        else nixpkgs.lib.nixosSystem;
      hmModule =
        if system == "aarch64-darwin"
        then home-manager.darwinModules.home-manager
        else home-manager.nixosModules.home-manager;
    in
      fn {
        inherit pkgs system;
        specialArgs = customSpecialArgs system;
        modules =
          [
            hostPath
            hmModule
            {
              home-manager.extraSpecialArgs = customSpecialArgs system;
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "hm.bak";
            }
          ]
          ++ (
            if system == "aarch64-darwin"
            then [mac-app-util.darwinModules.default]
            else []
          );
      };
  in {
    darwinConfigurations.suremac = mkHostWithModules ./configuration.nix;

    deploy.nodes.suremac = lib.mkDeploy' self.darwinConfigurations.suremac;
  };
}
