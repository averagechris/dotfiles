{
  description = "A flake containing the nixos configurations of most of my personal systems.";
  nixConfig = {
    extra-trusted-public-keys = "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs= nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA= averagechris-dotfiles.cachix.org-1:VwJkl5dG1+xGDY5x884mH/kVwwpgwBAdBKIF3BZiia4= devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw= helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs= cosmic.cachix.org-1:Dya9IyXD4xdBehWjrkPv6rtxpmMdRel02smYzA85dPE=";
    extra-substituters = "https://nix-community.cachix.org https://nixpkgs-wayland.cachix.org https://devenv.cachix.org https://averagechris-dotfiles.cachix.org https://helix.cachix.org https://cosmic.cachix.org/";
  };
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    calibre-web-fix.url = "github:getchoo-contrib/nixpkgs/pkgs/calibre-web/0.6.24";
    nixos-hardware.url = "github:nixos/nixos-hardware";
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    darwin = {
      url = "github:lnl7/nix-darwin/nix-darwin-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    helix = {
      url = "github:helix-editor/helix";
      inputs.nixpkgs.follows = "unstable";
    };
    mac-app-util.url = "github:hraban/mac-app-util";
    nixpkgs-firefox-darwin = {
      url = "github:bandithedoge/nixpkgs-firefox-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    titlecase = {
      url = "sourcehut:~averagechris/titlecase";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-cosmic = {
      url = "github:lilyinstarlight/nixos-cosmic";
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
          # taz = mkHost x86_64-linux ./hosts/taz.nix;
          thorny = mkHost x86_64-linux ./hosts/thelio.nix;
          tom = mkHost x86_64-linux ./hosts/tom.nix;
          tootsie = mkHost x86_64-linux ./hosts/tootsie.nix;
          cruber = mkHost x86_64-linux ./hosts/xps.nix;
          trap = mkHost x86_64-linux ./hosts/trap.nix;
        };
        darwinConfigurations.suremac = mkHost flake-utils.lib.system.aarch64-darwin ./nixpkgs/darwin/suremac;
        deploy.nodes = {
          tom = mkDeploy self.nixosConfigurations.tom;
          # taz = mkDeploy self.nixosConfigurations.taz;
          tootsie = mkDeploy self.nixosConfigurations.tootsie;
          trap = mkDeploy' self.nixosConfigurations.trap;
          cruber = mkDeploy' self.nixosConfigurations.cruber;
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
            nil # nix language server
            nixd
            nodePackages.bash-language-server
            self.outputs.packages.${system}.agenix
            self.inputs.deploy-rs.packages.${system}.deploy-rs

            # Rust development
            cargo
            rustc
            rustfmt
            clippy
            rust-analyzer
            pkg-config
            openssl.dev

            ruff
            python3Packages.python-lsp-server
            python3Packages.python-lsp-ruff
            python3Packages.pylsp-rope
          ];
        };
        checks = dotfiles.lib.mkCommitCheck system // (builtins.mapAttrs (sys: l: l.deployChecks self.deploy) self.inputs.deploy-rs.lib).${system};
      });
}
