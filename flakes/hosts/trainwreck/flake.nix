{
  description = "Trainwreck NixOS system configuration - Hetzner VPS for clawdbot";

  inputs = {
    base-lib.url = "path:../../base-lib";
    nixos-modules.url = "path:../../nixos-modules";
    hm-modules.url = "path:../../hm-modules";
    nixpkgs.follows = "base-lib/nixpkgs";
    home-manager.follows = "base-lib/home-manager";
    flake-utils.follows = "base-lib/flake-utils";
    agenix.follows = "base-lib/agenix";
    deploy-rs.follows = "base-lib/deploy-rs";
    titlecase.follows = "base-lib/titlecase";

    # Openclaw - personal AI assistant (fork with NixOS compatibility fixes)
    nix-openclaw = {
      url = "git+https://git.sr.ht/~averagechris/nix-openclaw";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Disko for declarative disk partitioning
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # starship-jj for jujutsu starship prompt integration
    starship-jj.url = "sourcehut:~averagechris/starship-jj";
  };

  outputs = inputs @ {
    self,
    base-lib,
    ...
  }: let
    system = "aarch64-linux";
    inherit (base-lib) lib;
  in {
    nixosConfigurations.trainwreck = lib.mkNixosHost {
      inherit system;
      hostPath = ./configuration.nix;
      extraInputs = inputs;
      extraOverlays = [inputs.nix-openclaw.overlays.default];
    };

    deploy.nodes.trainwreck = lib.mkDeploy self.nixosConfigurations.trainwreck;
  };
}
