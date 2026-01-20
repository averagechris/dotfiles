{
  description = "Tater NixOS system configuration (ThinkPad T14s Gen 5 AMD)";

  inputs = {
    base-lib.url = "path:../../base-lib";
    nixos-modules.url = "path:../../nixos-modules";
    hm-modules.url = "path:../../hm-modules";
    nixpkgs.follows = "base-lib/nixpkgs";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager.follows = "base-lib/home-manager";
    flake-utils.follows = "base-lib/flake-utils";
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
    hyprland = {
      url = "github:hyprwm/Hyprland";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprlock = {
      url = "github:hyprwm/hyprlock";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hypridle = {
      url = "github:hyprwm/hypridle";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    anyrun = {
      url = "github:anyrun-org/anyrun";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    base-lib,
    ...
  }: let
    system = "x86_64-linux";
    inherit (base-lib) lib;
  in {
    nixosConfigurations.tater = lib.mkNixosHost {
      inherit system;
      hostPath = ./configuration.nix;
      extraInputs = inputs;
    };

    deploy.nodes.tater = lib.mkDeploy' self.nixosConfigurations.tater;
  };
}
