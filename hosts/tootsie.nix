{pkgs, ...}: {
  imports = [
    ../nixpkgs/nixos/common.nix
    ../nixpkgs/nixos/networking.nix
    ../nixpkgs/nixos/tailscale.nix
    ../nixpkgs/nixos/users/chris-minimal.nix
    ./hardware-configurations/tootsie.nix
  ];

  boot.loader.grub.enable = true;

  # forwarding required for tailscale exit-node
  # https://tailscale.com/kb/1104/enable-ip-forwarding/
  boot.kernel.sysctl."net.ipv4.ip_forward" = true;
  boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = true;

  networking = {
    firewall.checkReversePath = "loose";
    hostName = "tootsie";
    useDHCP = false;
    defaultGateway = {
      address = "45.56.117.20";
      interface = "eth0";
    };
    usePredictableInterfaceNames = false;
    interfaces.eth0 = {
      useDHCP = true;
      ipv4.addresses = [
        {
          address = "45.56.117.20";
          prefixLength = 24;
        }
      ];
    };
    # https://discourse.nixos.org/t/nixos-on-linode/14825
    # Linode blocks all IPv6 traffic originating from your instance
    # except for traffic originating from your assigned address. If
    # you have temporary addresses enabled, traffic will originate
    # from them by default.
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

  system.stateVersion = "21.11";
  home-manager.users.chris = {
    pkgs,
    config,
    ...
  }: {
    home.stateVersion = "21.11";
    home.packages = with pkgs; [python311Packages.pipx];
    programs.meganz.enable = true;
    programs.zsh.initExtra = ''
      export PATH=$HOME/.local/bin:$PATH
    '';
  };

  time.timeZone = "UTC";

  # TODO extract into deployable module
  security.sudo = {
    wheelNeedsPassword = false;
    execWheelOnly = true;
  };
}
