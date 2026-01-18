{
  description = "Suremac Darwin system configuration";

  inputs = {
    base-lib.url = "path:../../base-lib";
    hm-modules.url = "path:../../hm-modules";
    darwin-modules.url = "path:../../darwin-modules";
    nixpkgs.follows = "base-lib/nixpkgs";
    darwin.follows = "base-lib/darwin";
    home-manager.follows = "base-lib/home-manager";
    flake-utils.follows = "base-lib/flake-utils";
    mac-app-util.follows = "base-lib/mac-app-util";
    agenix.follows = "base-lib/agenix";
    deploy-rs.follows = "base-lib/deploy-rs";
    titlecase.follows = "base-lib/titlecase";
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
    ...
  }: let
    inherit (base-lib) lib;
  in {
    darwinConfigurations.suremac = lib.mkDarwinHost {
      hostPath = ./configuration.nix;
      extraInputs = inputs;
    };
  };
}
