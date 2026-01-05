{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    inputs.nixos-modules.nixosModules.common
    inputs.nixos-modules.nixosModules.desktopCommon
    inputs.nixos-modules.nixosModules.tailscale
    inputs.nixos-modules.nixosModules.users.chrisMinimal
    inputs.nixos-modules.nixosModules.homeAssistant
    inputs.nixos-hardware.nixosModules.system76
    ./hardware.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  networking.hostName = "tom";
  networking.networkmanager.enable = false;
  time.timeZone = "America/New_York";
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
    settings.PasswordAuthentication = false;
  };
  system.stateVersion = "24.11";
  users.users.chris.extraGroups = ["calibre-web"];
  home-manager.users.chris = {...}: {
    home.stateVersion = "24.11";
  };

  # TODO extract into deployable module
  security.sudo = {
    wheelNeedsPassword = false;
    execWheelOnly = true;
  };

  services.calibre-web = {
    enable = true;

    openFirewall = true;
    listen.ip = "0.0.0.0";
    options.enableBookConversion = true;
    options.enableBookUploading = true;
  };
}
