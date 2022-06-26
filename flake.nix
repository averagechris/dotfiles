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
      # later revs up to edbe868dd5f8bf447eaffd4cff85167d0771ce0f
      # are giving me an issue with an autoloads missing file erorr
      url = "github:nix-community/nix-doom-emacs?rev=f1ca1906a5f0ff319cb08d9ab478cf377e327c92";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sli-repo = {
      url = "github:sureapp/sli";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    emacs-overlay,
    home-manager,
    nixos-hardware,
    nix-doom-emacs,
    wayland-overlay,
    pre-commit-hooks,
    ...
  } @ inputs: let
    overlays = [emacs-overlay.overlay wayland-overlay.overlay];
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    helloDotfiles = pkgs.writeShellApplication {
      name = "helloDotfiles";
      runtimeInputs = [pkgs.coreutils];
      text = ''
        printf "\n\n"
        echo 👋👋 hello from github:averagechris/dotfiles
        echo have a nice day 😎
        printf "\n\n"
      '';
    };

    thelio-nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {inherit inputs overlays;};
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
        ./nixpkgs/nixos/users/chris-focus.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
        }
      ];
    };

    xps-nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {inherit inputs overlays;};
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
        ./nixpkgs/nixos/users/chris-focus.nix
        ./nixpkgs/nixos/users/chris.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
        }
      ];
    };

    tootsie = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {inherit inputs overlays;};
      modules = [
        ./nixpkgs/nixos/tootsie
        ./nixpkgs/nixos/common.nix
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
      system = "x86_64-linux";
      specialArgs = {inherit inputs overlays;};
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
      ];
    };
  in {
    overlays = {
      emacs = emacs-overlay.overlay;
      wayland = wayland-overlay.overlay;
    };

    nixosConfigurations = {
      inherit
        taz
        thelio-nixos
        tootsie
        xps-nixos
        ;
    };

    packages.x86_64-linux.default = helloDotfiles;

    checks.x86_64-linux = {
      thelio-nixos = thelio-nixos.config.system.build.toplevel;
      xps-nixos = xps-nixos.config.system.build.toplevel;
      tootsie = tootsie.config.system.build.toplevel;
      taz = taz.config.system.build.toplevel;

      pre-commit = pre-commit-hooks.lib.x86_64-linux.run {
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
            entry = with pkgs.python310Packages; "${mdformat}/bin/mdformat";
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
    };

    devShells = {
      x86_64-linux.default = pkgs.mkShell {
        shellHook =
          self.checks.x86_64-linux.pre-commit.shellHook
          + ''
            helloDotfiles
          '';
        buildInputs = with pkgs; [
          alejandra
          cachix
          helloDotfiles
          mdl
          statix
          python310Packages.mdformat
        ];
      };
    };

    formatter.x86_64-linux = pkgs.alejandra;
  };
}
