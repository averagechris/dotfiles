{
  description = "Thorny NixOS system configuration";

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
    systems.url = "github:nix-systems/default-linux";
    agenix.follows = "base-lib/agenix";
    deploy-rs.follows = "base-lib/deploy-rs";
    titlecase.follows = "base-lib/titlecase";
    helix.follows = "hm-modules/helix";
    starship-jj.follows = "hm-modules/starship-jj";
    gander.follows = "hm-modules/gander";
    hyprland = {
      # Match tater's pinned Hyprland so the shared workstation config and
      # portal behavior stay consistent between daily GUI machines.
      url = "github:hyprwm/Hyprland/0002f148c9a4fe421a9d33c0faa5528cdc411e62";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
    };
    Hyprspace = {
      url = "github:KZDKM/Hyprspace";
      inputs.hyprland.follows = "hyprland";
      inputs.systems.follows = "systems";
    };
    hypridle = {
      url = "github:hyprwm/hypridle";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
    };
    anyrun = {
      url = "github:anyrun-org/anyrun";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
    };
    pip-chrome-extension = {
      url = "git+https://git.sr.ht/~averagechris/pip-chrome-extension";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hister = {
      url = "git+https://git.sr.ht/~averagechris/hister";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    base-lib,
    nixpkgs,
    ...
  }: let
    system = "x86_64-linux";
    inherit (base-lib) lib;
    pkgs = nixpkgs.legacyPackages.${system};
    thornySystem = lib.mkNixosHost {
      inherit system;
      hostPath = ./configuration.nix;
      extraInputs = inputs;
    };
    cfg = thornySystem.config;
    hm = cfg.home-manager.users.chris;
    greetdCommand = cfg.services.greetd.settings.default_session.command or "";
    greetdHyprlandConfigPath =
      if greetdCommand != ""
      then pkgs.lib.last (pkgs.lib.splitString " " greetdCommand)
      else "";
  in {
    nixosConfigurations.thorny = thornySystem;

    deploy.nodes.thorny = lib.mkDeploy self.nixosConfigurations.thorny;

    checks.${system} = {
      thorny-hyprland-greeter-config = lib.mkHyprlandConfigCheck {
        name = "thorny-hyprland-greeter-config";
        hyprlandPackage = cfg.programs.hyprland.package;
        configFile = greetdHyprlandConfigPath;
      };

      thorny-hyprland-home-config = lib.mkHyprlandConfigCheck {
        name = "thorny-hyprland-home-config";
        hyprlandPackage = hm.wayland.windowManager.hyprland.finalPackage;
        configFile = hm.xdg.configFile."hypr/hyprland.conf".source;
      };
    };
  };
}
