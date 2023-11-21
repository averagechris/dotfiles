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
    helix = {
      url = "github:helix-editor/helix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    flake-utils,
    ...
  }: let
    dotfiles.lib = import ./lib.nix {
      inherit inputs;
      inherit (inputs) nixpkgs;
    };
  in
    with dotfiles.lib;
      {
        nixosConfigurations = with flake-utils.lib.system; {
          gnome-work-vm = mkHost aarch64-linux ./hosts/gnome-work-vm.nix;
          # taz = mkHost x86_64-linux ./hosts/taz.nix;
          thelio-nixos = mkHost x86_64-linux ./hosts/thelio.nix;
          tom = mkHost x86_64-linux ./hosts/tom.nix;
          tootsie = mkHost x86_64-linux ./hosts/tootsie.nix;
          xps-nixos = mkHost x86_64-linux ./hosts/xps.nix;
          trap = mkHost x86_64-linux ./hosts/trap.nix;
        };
        darwinConfigurations.suremac = mkHost flake-utils.lib.system.aarch64-darwin ./nixpkgs/darwin/suremac;
        deploy.nodes = {
          tom = mkDeploy self.nixosConfigurations.tom;
          # taz = mkDeploy self.nixosConfigurations.taz;
          tootsie = mkDeploy self.nixosConfigurations.tootsie;
        };
      }
      // flake-utils.lib.eachDefaultSystem (system: let
        pkgs = self.inputs.nixpkgs.legacyPackages.${system};
      in {
        formatter = pkgs.alejandra;
        # deploy usage: nix run .#deploy -- .#tootsie
        apps.deploy = self.inputs.deploy-rs.apps.${system}.deploy-rs;
        packages.agenix = self.inputs.agenix.packages.${system}.default;
        devShells.default = pkgs.mkShell {
          inherit (self.checks.${system}.pre-commit) shellHook;
          buildInputs = with pkgs; [
            alejandra
            cachix
            mdl
            statix
            python311Packages.mdformat
            nil # nix language server
            nixd
            nodePackages.bash-language-server
            self.outputs.packages.${system}.agenix
            self.inputs.deploy-rs.packages.${system}.deploy-rs
          ];
        };
        checks = dotfiles.lib.mkCommitCheck system // (builtins.mapAttrs (sys: l: l.deployChecks self.deploy) self.inputs.deploy-rs.lib).${system};
      });
}
