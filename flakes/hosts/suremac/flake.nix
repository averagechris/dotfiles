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
      # Don't follow nixpkgs - use helix's own nixpkgs to get cached builds
      # from helix.cachix.org (avoids building Swift/dotnet for tree-sitter grammars)
      url = "github:helix-editor/helix";
    };
    starship-jj = {
      url = "sourcehut:~averagechris/starship-jj";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    linear-cli = {
      url = "sourcehut:~averagechris/linear-cli";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    gander = {
      url = "sourcehut:~averagechris/gander";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    granola-cli = {
      url = "sourcehut:~averagechris/granola-cli";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    slack = {
      url = "sourcehut:~averagechris/slack";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    ctx = {
      url = "sourcehut:~averagechris/ctx";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
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
