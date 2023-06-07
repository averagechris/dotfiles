{
  pkgs,
  config,
  lib,
  inputs,
  ...
}: {
  imports = [
    ../nixpkgs/nixos/common.nix
    ../nixpkgs/nixos/searx.nix
    ../nixpkgs/nixos/tailscale.nix
    ../nixpkgs/nixos/users/chris-minimal.nix
    ./hardware-configurations/taz.nix
    inputs.home-manager.nixosModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
    }
  ];

  boot.loader.grub.enable = true;

  networking = {
    firewall.checkReversePath = "loose";
    hostName = "taz";
    useDHCP = false;
    firewall.allowedTCPPorts = [80 443];
    defaultGateway = {
      address = "173.255.229.137";
      interface = "eth0";
    };
    usePredictableInterfaceNames = false;
    interfaces.eth0 = {
      useDHCP = true;
      ipv4.addresses = [
        {
          address = "173.255.229.137";
          prefixLength = 24;
        }
      ];
    };
    tempAddresses = "disabled";
  };

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
    settings.PasswordAuthentication = false;
  };

  environment.systemPackages = with pkgs; [
    inetutils
    mtr
    sysstat
  ];

  system.stateVersion = "22.05";
  home-manager.users.chris = {pkgs, ...}: {
    home.stateVersion = "22.05";
  };

  time.timeZone = "UTC";

  # TODO extract into deployable module
  security.sudo = {
    wheelNeedsPassword = false;
    execWheelOnly = true;
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "green.iron4199@fastmail.com";
  };

  services.nginx = {
    enable = true;
    user = "searx";
    proxyTimeout = "300s";
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    virtualHosts = {
      "search.thesogu.com" = {
        forceSSL = true;
        enableACME = true;
        serverAliases = ["search.thesogu.com"];
        locations."/" = {
          extraConfig = ''
            include ${config.services.nginx.package}/conf/uwsgi_params;
            uwsgi_pass unix:/run/searx/searx.sock;
          '';
        };
      };
    };
  };
}
