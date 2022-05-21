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
          ../users/chris-minimal.nix

          ({ pkgs, ... }: {

            boot.loader.grub.enable = true;
            boot.loader.grub.version = 2;

            # forwarding required for tailscale exit-node
            # https://tailscale.com/kb/1104/enable-ip-forwarding/
            boot.kernel.sysctl."net.ipv4.ip_forward" = true;
            boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = true;

            networking = {
              firewall.checkReversePath = "loose";
              hostName = "tootsie";
              useDHCP = false;
              defaultGateway = {
                address = "45.56.117.1";
                interface = "eth0";
              };
              usePredictableInterfaceNames = false;
              interfaces.eth0 = {
                useDHCP = true;
                ipv4.addresses = [
                  {
                    address = "45.56.117.1";
                    prefixLength = 24;
                  }
                ];
              };
            };

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
            home-manager.users.chris = { pkgs, ... }: {
              home.stateVersion = "21.11";
              home.packages = with pkgs; [ poetry ];
              imports = [ ../../meganz.nix ];
            };

            time.timeZone = "UTC";

            users.users.chris.openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGaGrbXoVGe5fXpOhG6+pUZw+aYANuiDPvoI82jftpPd chris@thesogu.com" # chris-thelio
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPflVyCskMX25z8S3pQLyGbo67zBQyC+eMbCkksRw4o/ chris@thesogu.com" # chris-xps
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
