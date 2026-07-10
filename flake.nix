{
  description = "Top-level aggregator flake for all dotfiles host configurations";

  inputs = {
    # Host flakes
    suremac = {
      url = "path:./flakes/hosts/suremac";
      inputs.base-lib.follows = "base-lib";
      inputs.hm-modules.follows = "hm-modules";
      inputs.darwin-modules.follows = "darwin-modules";
      inputs.starship-jj.follows = "hm-modules/starship-jj";
      inputs.linear-cli.follows = "hm-modules/linear-cli";
      inputs.gander.follows = "hm-modules/gander";
      inputs.sideshow.follows = "sideshow";
      inputs.srht.follows = "srht";
      inputs.ctx.follows = "ctx";
      inputs.rdny.follows = "rdny";
    };
    trap = {
      url = "path:./flakes/hosts/trap";
      inputs.base-lib.follows = "base-lib";
      inputs.nixos-modules.follows = "nixos-modules";
      inputs.hm-modules.follows = "hm-modules";
      inputs.nixos-hardware.follows = "nixos-hardware";
      inputs.helix.follows = "hm-modules/helix";
      inputs.starship-jj.follows = "hm-modules/starship-jj";
      inputs.gander.follows = "hm-modules/gander";
    };
    thorny = {
      url = "path:./flakes/hosts/thorny";
      inputs.base-lib.follows = "base-lib";
      inputs.nixos-modules.follows = "nixos-modules";
      inputs.hm-modules.follows = "hm-modules";
      inputs.nixos-hardware.follows = "nixos-hardware";
      inputs.helix.follows = "hm-modules/helix";
      inputs.starship-jj.follows = "hm-modules/starship-jj";
      inputs.gander.follows = "hm-modules/gander";
      inputs.srht.follows = "srht";
      inputs.hyprland.follows = "hyprland";
      inputs.Hyprspace.follows = "Hyprspace";
      inputs.hypridle.follows = "hypridle";
      inputs.anyrun.follows = "anyrun";
      inputs.pip-chrome-extension.follows = "pip-chrome-extension";
      inputs.systems.follows = "systems";
    };
    tom = {
      url = "path:./flakes/hosts/tom";
      inputs.base-lib.follows = "base-lib";
      inputs.nixos-modules.follows = "nixos-modules";
      inputs.hm-modules.follows = "hm-modules";
      inputs.nixos-hardware.follows = "nixos-hardware";
      inputs.helix.follows = "hm-modules/helix";
      inputs.starship-jj.follows = "hm-modules/starship-jj";
    };
    cruber = {
      url = "path:./flakes/hosts/cruber";
      inputs.base-lib.follows = "base-lib";
      inputs.nixos-modules.follows = "nixos-modules";
      inputs.hm-modules.follows = "hm-modules";
      inputs.nixos-hardware.follows = "nixos-hardware";
      inputs.helix.follows = "hm-modules/helix";
      inputs.starship-jj.follows = "hm-modules/starship-jj";
    };
    tater = {
      url = "path:./flakes/hosts/tater";
      inputs.base-lib.follows = "base-lib";
      inputs.nixos-modules.follows = "nixos-modules";
      inputs.hm-modules.follows = "hm-modules";
      inputs.nixos-hardware.follows = "nixos-hardware";
      inputs.helix.follows = "hm-modules/helix";
      inputs.starship-jj.follows = "hm-modules/starship-jj";
      inputs.gander.follows = "hm-modules/gander";
      inputs.sideshow.follows = "sideshow";
      inputs.srht.follows = "srht";
      inputs.hyprland.follows = "hyprland";
      inputs.Hyprspace.follows = "Hyprspace";
      inputs.hypridle.follows = "hypridle";
      inputs.anyrun.follows = "anyrun";
      inputs.pip-chrome-extension.follows = "pip-chrome-extension";
      inputs.disko.follows = "disko";
      inputs.ctx.follows = "ctx";
      inputs.rdny.follows = "rdny";
      inputs.systems.follows = "systems";
    };
    trainwreck = {
      url = "path:./flakes/hosts/trainwreck";
      inputs.base-lib.follows = "base-lib";
      inputs.nixos-modules.follows = "nixos-modules";
      inputs.hm-modules.follows = "hm-modules";
      inputs.disko.follows = "disko";
      inputs.starship-jj.follows = "hm-modules/starship-jj";
    };
    taz = {
      url = "path:./flakes/hosts/taz";
      inputs.base-lib.follows = "base-lib";
      inputs.nixos-modules.follows = "nixos-modules";
      inputs.hm-modules.follows = "hm-modules";
      inputs.nixos-hardware.follows = "nixos-hardware";
      inputs.helix.follows = "hm-modules/helix";
      inputs.starship-jj.follows = "hm-modules/starship-jj";
    };
    tootsie = {
      url = "path:./flakes/hosts/tootsie";
      inputs.base-lib.follows = "base-lib";
      inputs.nixos-modules.follows = "nixos-modules";
      inputs.hm-modules.follows = "hm-modules";
      inputs.nixos-hardware.follows = "nixos-hardware";
      inputs.helix.follows = "hm-modules/helix";
      inputs.starship-jj.follows = "hm-modules/starship-jj";
    };

    # Development dependencies
    base-lib.url = "path:./flakes/base-lib";
    nixos-modules = {
      url = "path:./flakes/nixos-modules";
      inputs.base-lib.follows = "base-lib";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    hm-modules = {
      url = "path:./flakes/hm-modules";
      inputs.base-lib.follows = "base-lib";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.home-manager.follows = "base-lib/home-manager";
      inputs.opencode.follows = "base-lib/opencode";
    };
    darwin-modules = {
      url = "path:./flakes/darwin-modules";
      inputs.base-lib.follows = "base-lib";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.home-manager.follows = "base-lib/home-manager";
      inputs.darwin.follows = "base-lib/darwin";
    };

    # Shared dependencies
    nixpkgs.follows = "base-lib/nixpkgs";
    flake-utils.follows = "base-lib/flake-utils";
    deploy-rs.follows = "base-lib/deploy-rs";
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ctx = {
      url = "sourcehut:~averagechris/ctx/dfc57f34a0861dee14507c9791649951750b1e52";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    srht = {
      url = "sourcehut:~averagechris/srht";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sideshow = {
      url = "sourcehut:~averagechris/sideshow";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rdny = {
      url = "sourcehut:~averagechris/rdny";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.srht.follows = "srht";
      inputs.fleet.inputs.nixpkgs.follows = "nixpkgs";
      inputs.fleet.inputs.srht.follows = "srht";
    };
    systems.url = "github:nix-systems/default-linux";
    hyprland = {
      # Pinned to the revision Hyprspace currently tests against so tater and
      # thorny share one compositor/portal lock graph.
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
      commonDevPackages = with pkgs; [
        alejandra
        cachix
        mdl
        shellcheck
        statix
        yj # for parsing .jj-lint.toml
        self.outputs.packages.${system}.dotfiles-maintenance-gate
        self.outputs.packages.${system}.update-flakes
        self.outputs.packages.${system}.agenix
        deploy-rs.packages.${system}.deploy-rs
      ];
      rustDevPackages = with pkgs; [
        cargo
        rustc
        rustfmt
        clippy
        pkg-config
        openssl.dev
      ];
      ideDevPackages = with pkgs; [
        nil # nix language server
        nixd
        pkgs."bash-language-server"
        rust-analyzer
      ];
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

      packages.dotfiles-maintenance-gate = pkgs.writeShellApplication {
        name = "dotfiles-maintenance-gate";
        runtimeInputs = [pkgs.coreutils pkgs.nix];
        text = builtins.readFile ./scripts/dotfiles-maintenance-gate.sh;
      };

      packages.flake-benchmark = pkgs.writeShellApplication {
        name = "flake-benchmark";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gitMinimal
          pkgs.jq
          pkgs.jujutsu
          pkgs.nix
          pkgs.time
        ];
        text = builtins.readFile ./scripts/flake-benchmark.sh;
      };

      packages.host-build-cache-benchmark = pkgs.writeShellApplication {
        name = "host-build-cache-benchmark";
        runtimeInputs = [pkgs.bash pkgs.coreutils pkgs.nix pkgs.time];
        text = builtins.readFile ./scripts/host-build-cache-benchmark.sh;
      };

      apps.update-flakes = {
        type = "app";
        program = "${self.packages.${system}.update-flakes}/bin/update-flakes";
        meta = {
          description = "Update enrolled flake inputs and fixed-hash packages";
        };
      };

      apps.dotfiles-maintenance-gate = {
        type = "app";
        program = "${self.packages.${system}.dotfiles-maintenance-gate}/bin/dotfiles-maintenance-gate";
        meta = {
          description = "Run the timed dotfiles maintenance check gate";
        };
      };

      apps.flake-benchmark = {
        type = "app";
        program = "${self.packages.${system}.flake-benchmark}/bin/flake-benchmark";
        meta = {
          description = "Benchmark dotfiles flake evaluation and write JSONL samples";
        };
      };

      apps.host-build-cache-benchmark = {
        type = "app";
        program = "${self.packages.${system}.host-build-cache-benchmark}/bin/host-build-cache-benchmark";
        meta.description = "Compare sequential and multi-installable fleet warm-up planning";
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
        packages = commonDevPackages;
      };

      devShells.rust = pkgs.mkShell {
        packages = commonDevPackages ++ rustDevPackages;
      };

      devShells.ide = pkgs.mkShell {
        packages = commonDevPackages ++ rustDevPackages ++ ideDevPackages;
      };
    });
}
