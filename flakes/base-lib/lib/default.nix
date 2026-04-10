{
  inputs,
  nixpkgs,
  flake-utils,
  home-manager,
  darwin,
  deploy-rs,
  agenix,
  mac-app-util,
  titlecase,
  sshKeys,
}: rec {
  # Helper library for options
  dotfiles_lib = {
    options = with inputs.nixpkgs.lib; {
      mkDefaultEnabledOption = description:
        mkOption {
          type = types.bool;
          default = true;
          example = false;
          inherit description;
        };
    };
  };

  # Generate special arguments for modules
  # Used by mkNixosHost and mkDarwinHost
  mkSpecialArgs = {
    system,
    extraInputs ? {},
  }: {
    inherit sshKeys system agenix dotfiles_lib;
    inputs = inputs // extraInputs;
    overlays = {
      default = final: prev: {};
    };
  };

  # Create a NixOS system configuration
  # This replaces the duplicated mkHostWithModules pattern in host flakes
  mkNixosHost = {
    system,
    hostPath,
    extraInputs ? {},
    permittedInsecurePackages ? [],
    extraOverlays ? [],
  }: let
    specialArgs = mkSpecialArgs {inherit system extraInputs;};
    pkgs = import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
        inherit permittedInsecurePackages;
      };
      overlays =
        [
          (final: prev: {
            titlecase =
              if extraInputs ? titlecase
              then extraInputs.titlecase.packages.${system}.default
              else inputs.titlecase.packages.${system}.default;
          })
          inputs.self.overlays.default
        ]
        ++ extraOverlays;
    };
  in
    nixpkgs.lib.nixosSystem {
      inherit pkgs system specialArgs;
      modules = [
        hostPath
        home-manager.nixosModules.home-manager
        ({config, ...}: {
          home-manager.extraSpecialArgs =
            specialArgs
            // {
              secrets =
                if config ? age
                then config.age.secrets
                else {};
            };
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "hm.bak";
        })
      ];
    };

  # Create a Darwin (macOS) system configuration
  # This replaces the duplicated mkHostWithModules pattern in host flakes
  mkDarwinHost = {
    system ? "aarch64-darwin",
    hostPath,
    extraInputs ? {},
  }: let
    specialArgs = mkSpecialArgs {inherit system extraInputs;};
    pkgs = import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
        allowUnsupportedSystem = true;
      };
      overlays = [
        (final: prev: {
          titlecase =
            if extraInputs ? titlecase
            then extraInputs.titlecase.packages.${system}.default
            else inputs.titlecase.packages.${system}.default;
        })
        inputs.self.overlays.default
      ];
    };
  in
    darwin.lib.darwinSystem {
      inherit pkgs system specialArgs;
      modules = [
        hostPath
        home-manager.darwinModules.home-manager
        mac-app-util.darwinModules.default
        agenix.darwinModules.default
        ({config, ...}: {
          home-manager.extraSpecialArgs =
            specialArgs
            // {
              secrets =
                if config ? age
                then config.age.secrets
                else {};
            };
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "hm.bak";
        })
      ];
    };

  # Legacy: kept for backwards compatibility but prefer mkNixosHost/mkDarwinHost
  specialArgs = system: mkSpecialArgs {inherit system;};

  # Legacy: Create a NixOS or Darwin system configuration
  # Prefer mkNixosHost or mkDarwinHost instead
  mkHost = system: hostPath: let
    isMacos = system == flake-utils.lib.system.aarch64-darwin;
  in
    if isMacos
    then mkDarwinHost {inherit system hostPath;}
    else mkNixosHost {inherit system hostPath;};

  # Create a deploy-rs configuration for a host
  mkDeploy = host: {
    hostname = host.config.networking.hostName;
    profiles.system = {
      sshOpts = ["-t"];
      user = "root";
      path = deploy-rs.lib.x86_64-linux.activate.nixos host;
      sshUser = "chris";
      fastConnection = true;
      magicRollback = false;
      autoRollback = false;
    };
  };

  # Create a deploy-rs configuration with interactive sudo
  mkDeploy' = host: {
    hostname = host.config.networking.hostName;
    profiles.system = {
      sshOpts = ["-t"];
      user = "root";
      path = deploy-rs.lib.x86_64-linux.activate.nixos host;
      sshUser = "chris";
      fastConnection = true;
      magicRollback = false;
      autoRollback = false;
      interactiveSudo = true;
    };
  };
}
