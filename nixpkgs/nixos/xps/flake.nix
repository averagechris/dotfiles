{
  description = "My XPS desktop config";

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
      # inputs.nixpkgs.follows = "cmpkgs";
      # inputs.master.follows = "master";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-doom-emacs = {
      url = "github:nix-community/nix-doom-emacs?rev=f1ca1906a5f0ff319cb08d9ab478cf377e327c92";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sli-repo = {
      url = "git+ssh://git@github.com/sureapp/sli";
      flake = false;
    };

  };

  outputs =
    { self
    , nixpkgs
    , emacs-overlay
    , home-manager
    , nixos-hardware
    , nix-doom-emacs
    , wayland-overlay
    , ...
    }@inputs: rec {

      system = "x86_64-linux";
      overlays = [ emacs-overlay.overlay wayland-overlay.overlay ];

      nixosConfigurations."xps-nixos" = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs overlays; };
        modules = [
          ./hardware-configuration.nix
          nixos-hardware.nixosModules.dell-xps-13-9310
          ../common.nix
          ../desktop_common.nix
          ../graphical.nix
          ../greetd.nix
          ../networking.nix
          ../docker.nix
          ../sound.nix
          ../tailscale.nix
          ../users/chris.nix
          ../users/chris-focus.nix

          ({ pkgs, ... }: {
            boot.initrd.luks.devices.root.device = "/dev/nvme0n1p2";
            networking.hostName = "xps-nixos";

            networking.wireless.interfaces = [ "wlp0s20f3" ];
            networking.interfaces.wlp6s0.useDHCP = false;

            # these opengl is needed for sway to work right on intel graphics
            hardware.opengl.enable = true;
            hardware.opengl.driSupport = true;

            system.stateVersion = "21.05";
            home-manager.users.chris = { pkgs, ... }: {
              home.stateVersion = "21.05";
            };

            boot.kernelModules = [
              "ipt_dnat"
              "ipt_mark"
              "iptable_filter"
              "iptable_nat"
              "sch_cake"
              "xt_nat"
            ];

          })

          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
          }

        ];
      };

    };
}
