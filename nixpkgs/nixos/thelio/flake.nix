{
  description = "My Thelio desktop config";

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
    }@inputs:

    let
      overlays = [ emacs-overlay.overlay wayland-overlay.overlay ];
      system = "x86_64-linux";
    in
    {
      inherit overlays system;

      nixosConfigurations."thelio-nixos" = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs overlays; };
        modules = [
          ./hardware-configuration.nix
          nixos-hardware.nixosModules.system76
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
            boot.initrd.luks.devices.root.device = "/dev/sda2";
            networking.hostName = "thelio-nixos";

            networking.wireless.interfaces = [ "wlp6s0" ];

            # dhcp and network manager are causinng issues
            # https://github.com/NixOS/nixpkgs/issues/152288
            networking.interfaces.enp5s0.useDHCP = true;
            networking.interfaces.enp7s0f3u4u3u4.useDHCP = true;
            networking.interfaces.wlp6s0.useDHCP = true;

            # system76 doesn't use fwupd / fwupdmgr, they have their own cli
            environment.systemPackages = [ pkgs.system76-firmware ];
            programs.steam.enable = true;

            virtualisation.virtualbox.host.enable = true;
            virtualisation.virtualbox.host.enableWebService = true;

            system.stateVersion = "21.05";
            home-manager.users.chris = { pkgs, ... }: {
              home.stateVersion = "21.05";
            };

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
