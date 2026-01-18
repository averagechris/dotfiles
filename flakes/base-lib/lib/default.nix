{
  inputs,
  nixpkgs,
  flake-utils,
  home-manager,
  darwin,
  deploy-rs,
  pre-commit-hooks,
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
          description = description;
        };
    };
  };

  # Generate special arguments for modules
  specialArgs = system: {
    inherit inputs sshKeys system agenix dotfiles_lib;
    overlays =
      (import ../overlays/default.nix {
        inherit inputs nixpkgs titlecase;
      }).default
      system;
  };

  # Create a NixOS or Darwin system configuration
  mkHost = system: hostPath: let
    isMacos = system == flake-utils.lib.system.aarch64-darwin;
    pkgs = import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
        allowUnsupportedSystem = isMacos;
        allowBroken = isMacos;
        # Required for home-assistant on tom.nix which needs legacy OpenSSL
        permittedInsecurePackages =
          if hostPath == ./hosts/tom.nix
          then ["openssl-1.1.1w"]
          else [];
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
      specialArgs = specialArgs system;
      modules =
        [
          hostPath
          hmModule
          {
            home-manager.extraSpecialArgs = specialArgs system;
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

  # Create pre-commit checks
  mkCommitCheck = system: {
    pre-commit = pre-commit-hooks.lib.${system}.run {
      src = builtins.path {
        path = ../../../.;
        name = "source";
      };
      hooks = {
        alejandra.enable = true;
        statix.enable = true;
        shellcheck.enable = true;
        markdown-formatter = {
          enable = false;
          name = "markdown-formatter";
          types = ["markdown"];
          language = "system";
          pass_filenames = true;
          # entry = with inputs.nixpkgs.legacyPackages.${system}.python311Packages; "${mdformat}/bin/mdformat";
        };
        markdown-linter = {
          enable = false;
          name = "markdown-linter";
          types = ["markdown"];
          language = "system";
          pass_filenames = true;
          # entry = with inputs.nixpkgs.legacyPackages.${system}; "${mdl}/bin/mdl -g";
        };
      };
    };
  };
}
