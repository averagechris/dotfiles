{
  description = "My Thelio desktop config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-21.11";
  };

  outputs = { self, nixpkgs }: {

    nixosConfigurations."thelio-nixos" = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hardware-configuration.nix
        ../common.nix
        ../greetd.nix
        ../gtk.nix
        ../networking.nix
        ../podman.nix
        ../sound.nix
        ../users.nix

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

      ];
    };

  };
}
