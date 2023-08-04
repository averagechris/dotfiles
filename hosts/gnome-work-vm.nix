{pkgs, ...}: {
  imports = [
    ../nixpkgs/nixos/users/gnome-work-vm-chris.nix
    ../nixpkgs/nixos/common.nix
    ../nixpkgs/nixos/docker.nix
    ../nixpkgs/nixos/tailscale.nix
    ../nixpkgs/nixos/is_remote_builder.nix
    ./hardware-configurations/gnome-work-vm.nix
  ];

  systemd.network.wait-online.enable = false; # we don't use this if we're using network manager
  systemd.services.NetworkManager-wait-online.enable = false;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot/efi";
  networking.hostName = "gnome-work-vm";
  networking.networkmanager.enable = true;
  networking.firewall.allowedTCPPorts = [22];
  time.timeZone = "America/Chicago";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };
  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;
  services.xserver = {
    layout = "us";
    xkbVariant = "";
  };
  security.rtkit.enable = true;
  services.xserver.libinput.enable = true;
  services.xserver.displayManager.autoLogin.enable = true;
  services.xserver.displayManager.autoLogin.user = "chris";

  # Workaround for GNOME autologin: https://github.com/NixOS/nixpkgs/issues/103746#issuecomment-945091229
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;
  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [
    gnomeExtensions.pop-shell
    gnomeExtensions.pop-launcher-super-key
    gnome.gnome-tweaks
  ];
  system.stateVersion = "22.11";
  virtualisation.vmware.guest.enable = false;
  services.flatpak.enable = true;
}
