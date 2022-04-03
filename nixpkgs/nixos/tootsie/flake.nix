{
  description = "Configuration for tootsie, currently hosted on linode.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self
    , nixpkgs
    , home-manager
    , ...
    }@inputs:

    let
      overlays = [ ];
      system = "x86_64-linux";
    in
    {
      inherit overlays system;

      nixosConfigurations."tootsie" = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs overlays; };
        modules = [
          ./hardware-configuration.nix
          ../common.nix
          ../tailscale.nix

          ({ pkgs, ... }: {

            boot.loader.grub.enable = true;
            boot.loader.grub.version = 2;


            networking.hostName = "tootsie";
            networking.useDHCP = false;
            networking.interfaces.enp0s5.useDHCP = true;
            networking.usePredictableInterfaceNames = false;
            networking.interfaces.eth0.useDHCP = true;

            services.openssh = {
              enable = true;
              permitRootLogin = "no";
            };

            environment.systemPackages = with pkgs; [
              inetutils
              mtr
              sysstat
            ];

            system.stateVersion = "21.11";

            time.timeZone = "UTC";

            users.users.chris = {
              isNormalUser = true;
              home = "/home/chris";
              description = "Chris User";
              extraGroups = [ "wheel" "networkmanager" ];
              openssh.authorizedKeys.keys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGaGrbXoVGe5fXpOhG6+pUZw+aYANuiDPvoI82jftpPd chris@thesogu.com" # chris-thelio
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPflVyCskMX25z8S3pQLyGbo67zBQyC+eMbCkksRw4o/ chris@thesogu.com" # chris-xps
              ];
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
