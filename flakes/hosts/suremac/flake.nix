{
  description = "Suremac Darwin system configuration";

  inputs = {
    base-lib.url = "path:../../base-lib";
    nixpkgs.follows = "base-lib/nixpkgs";
    hm-modules = {
      url = "path:../../hm-modules";
      inputs.base-lib.follows = "base-lib";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.home-manager.follows = "home-manager";
      inputs.opencode.follows = "base-lib/opencode";
      inputs.nitter-link.follows = "nitter-link";
    };
    darwin-modules = {
      url = "path:../../darwin-modules";
      inputs.base-lib.follows = "base-lib";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.home-manager.follows = "home-manager";
      inputs.darwin.follows = "darwin";
    };
    darwin.follows = "base-lib/darwin";
    home-manager.follows = "base-lib/home-manager";
    flake-utils.follows = "base-lib/flake-utils";
    agenix.follows = "base-lib/agenix";
    deploy-rs.follows = "base-lib/deploy-rs";
    titlecase.follows = "base-lib/titlecase";
    helix = {
      # Don't follow nixpkgs - use helix's own nixpkgs to get cached builds
      # from helix.cachix.org (avoids building Swift/dotnet for tree-sitter grammars)
      url = "github:helix-editor/helix";
    };
    starship-jj.follows = "hm-modules/starship-jj";
    linear-cli.follows = "hm-modules/linear-cli";
    gander.follows = "hm-modules/gander";
    srht = {
      url = "sourcehut:~averagechris/srht";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    granola-cli = {
      url = "sourcehut:~averagechris/granola-cli";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    sideshow = {
      url = "sourcehut:~averagechris/sideshow";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rdny = {
      url = "sourcehut:~averagechris/rdny";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.fleet.inputs.nixpkgs.follows = "nixpkgs";
      inputs.fleet.inputs.srht.follows = "srht";
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
    nitter-link = {
      url = "git+https://git.sr.ht/~averagechris/nitter-link?ref=refs/tags/v0.1.4";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
      inputs.fleet.inputs.nixpkgs.follows = "nixpkgs";
      inputs.fleet.inputs.srht.follows = "srht";
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
