{
  description = "Personal MacBook Pro Darwin configuration";

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
      inputs.fleet.follows = "fleet";
      inputs.fleet-srht.follows = "fleet-srht";
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
    fleet = {
      url = "github:averagechris/averagechris.github.io";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Fleet's publishing/build apps use this package internally; it is not
    # installed as a host CLI.
    fleet-srht = {
      url = "github:averagechris/srht";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.fleet.follows = "fleet";
    };

    ctx = {
      url = "github:averagechris/ctx";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.fleet.follows = "fleet";
    };
    nitter-link = {
      url = "github:averagechris/nitter-link/v0.1.4";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
      inputs.fleet.follows = "fleet";
    };

    memo = {
      url = "github:averagechris/memo";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {base-lib, ...}: {
    darwinConfigurations.taro = base-lib.lib.mkDarwinHost {
      system = "aarch64-darwin";
      hostPath = ./configuration.nix;
      extraInputs = inputs;
    };
  };
}
