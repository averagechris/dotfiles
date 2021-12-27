{
  description = "My Thelio desktop config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:nixos/nixos-hardware";
    emacs-overlay.url = "github:nix-community/emacs-overlay";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-doom-emacs = {
      url = "github:nix-community/nix-doom-emacs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs =
    { self
    , nixpkgs
    , emacs-overlay
    , home-manager
    , nixos-hardware
    , nix-doom-emacs
    ,
    }@inputs: {

      overlays = [ emacs-overlay ];

      nixosConfigurations."thelio-nixos" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          ./hardware-configuration.nix
          nixos-hardware.nixosModules.system76
          ../common.nix
          ../greetd.nix
          ../gtk.nix
          ../networking.nix
          ../podman.nix
          ../sound.nix
          ../users/chris.nix

          ({ pkgs, ... }: {
            boot.initrd.luks.devices.root.device = "/dev/sda2";
            networking.hostName = "thelio-nixos";

            networking.wireless.interfaces = [ "wlp6s0" ];
            networking.interfaces.enp5s0.useDHCP = true;
            networking.interfaces.enp7s0f3u4u3u4.useDHCP = true;
            networking.interfaces.wlp6s0.useDHCP = true;

            # system76 doesn't use fwupd / fwupdmgr, they have their own cli
            environment.systemPackages = [ pkgs.system76-firmware ];

            system.stateVersion = "21.05";

          })

          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.chris = { pkgs, ... }: {
              imports = [
                { nixpkgs.overlays = self.overlays; }
                ../../home.nix
                nix-doom-emacs.hmModule
              ];
            };
          }

        ];
      };

    };
}
