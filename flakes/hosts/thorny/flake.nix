{
  description = "Thorny NixOS system configuration";

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
      # Match tater's pinned Hyprland so the shared workstation config and
      # portal behavior stay consistent between daily GUI machines.
      url = "github:hyprwm/Hyprland/0002f148c9a4fe421a9d33c0faa5528cdc411e62";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    Hyprspace = {
      url = "github:KZDKM/Hyprspace";
      inputs.hyprland.follows = "hyprland";
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
    nixosConfigurations.thorny = lib.mkNixosHost {
      inherit system;
      hostPath = ./configuration.nix;
      extraInputs = inputs;
    };

    deploy.nodes.thorny = lib.mkDeploy self.nixosConfigurations.thorny;
  };
}
