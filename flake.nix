{
  description = "Top-level aggregator flake for all dotfiles host configurations";

  inputs = {
    # Host flakes
    suremac.url = "path:./flakes/hosts/suremac";
    trap.url = "path:./flakes/hosts/trap";
    thorny.url = "path:./flakes/hosts/thorny";
    tom.url = "path:./flakes/hosts/tom";
    cruber.url = "path:./flakes/hosts/cruber";
    tater.url = "path:./flakes/hosts/tater";
    trainwreck.url = "path:./flakes/hosts/trainwreck";
    taz.url = "path:./flakes/hosts/taz";
    tootsie.url = "path:./flakes/hosts/tootsie";

    # Development dependencies
    base-lib.url = "path:./flakes/base-lib";
    nixos-modules.url = "path:./flakes/nixos-modules";
    hm-modules.url = "path:./flakes/hm-modules";
    darwin-modules.url = "path:./flakes/darwin-modules";

    # Shared dependencies
    nixpkgs.follows = "base-lib/nixpkgs";
    flake-utils.follows = "base-lib/flake-utils";
    deploy-rs.follows = "base-lib/deploy-rs";
  };

  outputs = inputs @ {
    self,
    suremac,
    trap,
    thorny,
    tom,
    cruber,
    tater,
    trainwreck,
    taz,
    tootsie,
    base-lib,
    flake-utils,
    deploy-rs,
    ...
  }: let
    inherit (base-lib) lib;
  in
    {
      # Re-export all NixOS configurations
      nixosConfigurations = {
        inherit (trap.nixosConfigurations) trap;
        inherit (thorny.nixosConfigurations) thorny;
        inherit (tom.nixosConfigurations) tom;
        inherit (cruber.nixosConfigurations) cruber;
        inherit (tater.nixosConfigurations) tater;
        inherit (trainwreck.nixosConfigurations) trainwreck;
        inherit (taz.nixosConfigurations) taz;
        inherit (tootsie.nixosConfigurations) tootsie;
      };

      # Re-export all Darwin configurations
      darwinConfigurations = {
        inherit (suremac.darwinConfigurations) suremac;
      };

      # Re-export all deploy nodes
      deploy.nodes = {
        inherit (trap.deploy.nodes) trap;
        inherit (thorny.deploy.nodes) thorny;
        inherit (tom.deploy.nodes) tom;
        inherit (cruber.deploy.nodes) cruber;
        inherit (tater.deploy.nodes) tater;
        inherit (trainwreck.deploy.nodes) trainwreck;
        inherit (taz.deploy.nodes) taz;
        inherit (tootsie.deploy.nodes) tootsie;
      };
    }
    // flake-utils.lib.eachDefaultSystem (system: let
      pkgs = inputs.nixpkgs.legacyPackages.${system};
    in {
      formatter = pkgs.alejandra;

      # Aggregate checks from all host flakes so the top-level `nix flake check`
      # catches regressions without needing to run per-host flake checks
      # manually. Strict duplicates (same value under the same name) are kept
      # once; name collisions with different values throw.
      checks = lib.mergeFlakeChecks [
        suremac.checks.${system} or {}
        trap.checks.${system} or {}
        thorny.checks.${system} or {}
        tom.checks.${system} or {}
        cruber.checks.${system} or {}
        tater.checks.${system} or {}
        trainwreck.checks.${system} or {}
        taz.checks.${system} or {}
        tootsie.checks.${system} or {}
      ];

      # deploy usage: nix run .#deploy -- .#hostname
      apps.deploy =
        deploy-rs.apps.${system}.deploy-rs
        // {
          meta = {
            description = "Deploy a NixOS host with deploy-rs";
          };
        };

      packages.deploy-quiet = pkgs.writeShellApplication {
        name = "deploy-quiet";
        runtimeInputs = [pkgs.nix];
        text = builtins.readFile ./scripts/deploy-quiet.sh;
      };

      packages.update-flakes = pkgs.rustPlatform.buildRustPackage {
        pname = "dotfiles-update-flakes";
        version = "0.1.0";
        src = ./tools/update-flakes;
        cargoLock.lockFile = ./tools/update-flakes/Cargo.lock;
        nativeBuildInputs = [pkgs.makeWrapper];
        postInstall = ''
          wrapProgram "$out/bin/update-flakes" \
            --prefix PATH : ${pkgs.lib.makeBinPath [pkgs.curl pkgs.nix]}
        '';
      };

      apps.update-flakes = {
        type = "app";
        program = "${self.packages.${system}.update-flakes}/bin/update-flakes";
        meta = {
          description = "Update enrolled flake inputs and fixed-hash packages";
        };
      };

      # Quiet deploy wrapper: nix run .#deploy-quiet -- hostname
      apps.deploy-quiet = {
        type = "app";
        program = "${self.packages.${system}.deploy-quiet}/bin/deploy-quiet";
        meta = {
          description = "Run a quieter target-scoped deploy-rs workflow";
        };
      };

      # Setup script for Darwin
      packages.setup-darwin-determinate-substituters = pkgs.writeShellApplication {
        name = "setup-darwin-determinate-substituters";
        text = builtins.readFile ./scripts/setup-darwin-determinate-nix.sh;
      };

      apps.setup-darwin-determinate-substituters = {
        type = "app";
        program = "${self.packages.${system}.setup-darwin-determinate-substituters}/bin/setup-darwin-determinate-substituters";
        meta = {
          description = "Configure Determinate Nix substituters on Darwin";
        };
      };

      # agenix package
      packages.agenix = base-lib.inputs.agenix.packages.${system}.default;

      # Development shell
      devShells.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          alejandra
          cachix
          mdl
          shellcheck
          statix
          yj # for parsing .jj-lint.toml
          nil # nix language server
          nixd
          pkgs."bash-language-server"
          self.outputs.packages.${system}.update-flakes
          self.outputs.packages.${system}.agenix
          deploy-rs.packages.${system}.deploy-rs

          # Rust development
          cargo
          rustc
          rustfmt
          clippy
          rust-analyzer
          pkg-config
          openssl.dev
        ];
      };
    });
}
