{
  pkgs,
  config,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader.grub.enable = true;
  boot.loader.grub.version = 2;

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

  system.stateVersion = "22.05";
  home-manager.users.chris = {pkgs, ...}: {
    home.stateVersion = "22.05";
  };

  time.timeZone = "UTC";

  users.users.chris.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGaGrbXoVGe5fXpOhG6+pUZw+aYANuiDPvoI82jftpPd chris@thesogu.com" # chris-thelio
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPflVyCskMX25z8S3pQLyGbo67zBQyC+eMbCkksRw4o/ chris@thesogu.com" # chris-xps
  ];

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
