{
  description = "A flake containing the nixos configurations of most of my personal systems.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:nixos/nixos-hardware";
    emacs-overlay = {
      url = "github:nix-community/emacs-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    wayland-overlay = {
      url = "github:nix-community/nixpkgs-wayland";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-doom-emacs = {
      url = "github:nix-community/nix-doom-emacs";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    sli-repo = {
      url = "github:sureapp/sli";
      flake = false;
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    darwin = {
      url = "github:lnl7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    agenix,
    darwin,
    deploy-rs,
    emacs-overlay,
    flake-utils,
    home-manager,
    nix-doom-emacs,
    nixos-hardware,
    nixpkgs,
    pre-commit-hooks,
    sli-repo,
    wayland-overlay,
    ...
  }: let
    sshKeys = rec {
      chris.thelio = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGaGrbXoVGe5fXpOhG6+pUZw+aYANuiDPvoI82jftpPd chris@thesogu.com";
      chris.xps = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPflVyCskMX25z8S3pQLyGbo67zBQyC+eMbCkksRw4o/ chris@thesogu.com";
      system.thelio = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDOiCjIMganzY45qiHFEO2NqkXz2mWsSEmq3zIoRJsiA root@nixos";
      system.xps = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAy30vzaxmqc08+NcYYA7LflDqoZNdRoyVXVJ2H9p2Xp root@xps-nixos";
      usesRemoteBuilders = {
        inherit (system) thelio xps;
      };
    };
    specialArgs = {
      inherit sshKeys sli-repo;
      nix-doom-emacs-module = nix-doom-emacs.hmModule;
      overlays = {
        emacs = emacs-overlay.overlay;
        wayland = wayland-overlay.overlay;
      };
    };
    systemKinds = flake-utils.lib.system;
  in
    flake-utils.lib.eachDefaultSystem (sys: let
      overlays = builtins.attrValues overlays;
      pkgs = nixpkgs.legacyPackages.${sys};
    in {
      packages = rec {
        hello = pkgs.writeShellApplication {
          name = "helloDotfiles";
          runtimeInputs = [pkgs.coreutils];
          text = ''
            printf "\n\n"
            echo 👋👋 hello from ~averagechris/dotfiles
            echo have a nice day 😎
            printf "\n\n"
          '';
        };
        default = hello;
      };
      apps = {
        deploy = deploy-rs.apps.${sys}.deploy-rs;
      };

      checks =
        {
          pre-commit = pre-commit-hooks.lib.${sys}.run {
            src = ./.;
            hooks = {
              alejandra.enable = true;
              statix.enable = true;
              shellcheck.enable = true;
              markdown-formatter = {
                enable = true;
                name = "markdown-formatter";
                types = ["markdown"];
                language = "system";
                pass_filenames = true;
                entry = with pkgs.python311Packages; "${mdformat}/bin/mdformat";
              };
              markdown-linter = {
                enable = true;
                name = "markdown-linter";
                types = ["markdown"];
                language = "system";
                pass_filenames = true;
                entry = with pkgs; "${mdl}/bin/mdl -g";
              };
            };
          };
        }
        // (
          if sys == systemKinds.x86_64-linux
          then {
            # these checks take ~4GB of memory right now to run
            # since nix flake check loads all of outputs.nixosConfigurations
            # into memory at once 😢
            thelio-nixos = self.outputs.nixosConfigurations.thelio-nixos.config.system.build.toplevel;
            xps-nixos = self.outputs.nixosConfigurations.xps-nixos.config.system.build.toplevel;
            tootsie = self.outputs.nixosConfigurations.tootsie.config.system.build.toplevel;
            taz = self.outputs.nixosConfigurations.taz.config.system.build.toplevel;
            tom = self.outputs.nixosConfigurations.tom.config.system.build.toplevel;
          }
          else {}
        )
        // (builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib).${sys};

      devShells = {
        default = pkgs.mkShell {
          shellHook =
            self.checks.${sys}.pre-commit.shellHook
            + ''
              helloDotfiles
            '';
          buildInputs = with pkgs; [
            alejandra
            cachix
            self.outputs.packages.${sys}.hello
            mdl
            statix
            python311Packages.mdformat
          ];
        };
      };

      formatter = pkgs.alejandra;
    })
    // rec {
      inherit (specialArgs) overlays;
      nixosConfigurations = {
        gnome-work-vm = nixpkgs.lib.nixosSystem {
          system = systemKinds.aarrch64-linux;
          inherit specialArgs;
          modules = [
            ./nixpkgs/nixos/gnome-work-vm/configuration.nix
            ./nixpkgs/nixos/users/gnome-work-vm-chris.nix
            ./nixpkgs/nixos/common.nix
            ./nixpkgs/nixos/docker.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
            }
          ];
        };
        thelio-nixos = nixpkgs.lib.nixosSystem {
          inherit specialArgs;
          system = systemKinds.x86_64-linux;
          modules = [
            ./nixpkgs/nixos/thelio
            nixos-hardware.nixosModules.system76
            ./nixpkgs/nixos/common.nix
            ./nixpkgs/nixos/desktop_common.nix
            ./nixpkgs/nixos/graphical.nix
            ./nixpkgs/nixos/greetd.nix
            ./nixpkgs/nixos/networking.nix
            ./nixpkgs/nixos/docker.nix
            ./nixpkgs/nixos/sound.nix
            ./nixpkgs/nixos/tailscale.nix
            ./nixpkgs/nixos/users/chris.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
            }
            agenix.nixosModules.default
            ./nixpkgs/nixos/use_remote_builds.nix
          ];
        };

        xps-nixos = nixpkgs.lib.nixosSystem {
          inherit specialArgs;
          system = systemKinds.x86_64-linux;
          modules = [
            ./nixpkgs/nixos/xps
            nixos-hardware.nixosModules.system76
            ./nixpkgs/nixos/common.nix
            ./nixpkgs/nixos/desktop_common.nix
            ./nixpkgs/nixos/docker.nix
            ./nixpkgs/nixos/graphical.nix
            ./nixpkgs/nixos/greetd.nix
            ./nixpkgs/nixos/networking.nix
            ./nixpkgs/nixos/sound.nix
            ./nixpkgs/nixos/tailscale.nix
            ./nixpkgs/nixos/users/chris.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
            }
            agenix.nixosModules.default
          ];
        };

        tootsie = nixpkgs.lib.nixosSystem {
          inherit specialArgs;
          system = systemKinds.x86_64-linux;
          modules = [
            ./nixpkgs/nixos/tootsie
            ./nixpkgs/nixos/common.nix
            ./nixpkgs/nixos/networking.nix
            ./nixpkgs/nixos/tailscale.nix
            ./nixpkgs/nixos/users/chris-minimal.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
            }
          ];
        };

        taz = nixpkgs.lib.nixosSystem {
          inherit specialArgs;
          system = systemKinds.x86_64-linux;
          modules = [
            ./nixpkgs/nixos/taz
            ./nixpkgs/nixos/common.nix
            ./nixpkgs/nixos/searx.nix
            ./nixpkgs/nixos/tailscale.nix
            ./nixpkgs/nixos/users/chris-minimal.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
            }
            ./nixpkgs/nixos/is_remote_builder.nix
          ];
        };

        tom = nixpkgs.lib.nixosSystem {
          inherit specialArgs;
          system = systemKinds.x86_64-linux;
          modules = [
            nixos-hardware.nixosModules.system76
            ./nixpkgs/nixos/tom
            ./nixpkgs/nixos/common.nix
            ./nixpkgs/nixos/tailscale.nix
            ./nixpkgs/nixos/users/chris-minimal.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
            }
            ./nixpkgs/nixos/home-assistant
          ];
        };
      };

      darwinConfigurations.suremac = darwin.lib.darwinSystem {
        system = systemKinds.aarch64-darwin;
        modules = [./nixpkgs/darwin/suremac];
      };

      deploy.nodes = {
        tom = {
          hostname = "tom";
          profiles.system = {
            sshOpts = ["-t"];
            user = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.tom;
            sshUser = "chris";
            fastConnection = true;
            magicRollback = false;
            autoRollback = false;
          };
        };
        taz = {
          hostname = "taz";
          profiles.system = {
            sshOpts = ["-t"];
            user = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.taz;
            sshUser = "chris";
            fastConnection = true;
            magicRollback = false;
            autoRollback = false;
          };
        };
        tootsie = {
          hostname = "tootsie";
          profiles.system = {
            sshOpts = ["-t"];
            user = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.tootsie;
            sshUser = "chris";
            fastConnection = true;
            magicRollback = false;
            autoRollback = false;
          };
        };
      };
    };
}
