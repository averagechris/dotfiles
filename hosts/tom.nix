{
  inputs,
  pkgs,
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
  environment.systemPackages = with pkgs; [
    git
    neovim
  ];
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
    settings.PasswordAuthentication = false;
  };
  system.stateVersion = "22.11";
  home-manager.users.chris = {pkgs, ...}: {
    home.stateVersion = "22.11";
  };

  # TODO extract into deployable module
  security.sudo = {
    wheelNeedsPassword = false;
    execWheelOnly = true;
  };
}
