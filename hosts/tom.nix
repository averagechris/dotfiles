{
  inputs,
  system,
  ...
}: {
  imports = [
    ./hardware-configurations/tom.nix
    ../nixpkgs/nixos/common.nix
    ../nixpkgs/nixos/tailscale.nix
    ../nixpkgs/nixos/users/chris-minimal.nix
    ../nixpkgs/nixos/home-assistant
    inputs.nixos-hardware.nixosModules.system76
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  networking.hostName = "tom";
  networking.networkmanager.enable = false;
  time.timeZone = "America/Chicago";
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
    settings.PasswordAuthentication = false;
  };
  system.stateVersion = "22.11";
  users.users.chris.extraGroups = ["calibre-web"];
  home-manager.users.chris = {...}: {
    home.stateVersion = "22.11";
  };

  # TODO extract into deployable module
  security.sudo = {
    wheelNeedsPassword = false;
    execWheelOnly = true;
  };

  services.calibre-web = {
    enable = true;
    package = inputs.calibre-web-fix.legacyPackages.${system}.calibre-web;

    openFirewall = true;
    listen.ip = "0.0.0.0";
    options.enableBookConversion = true;
    options.enableBookUploading = true;
  };
}
