{
  config,
  pkgs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  networking.hostName = "tom";
  networking.networkmanager.enable = true;
  time.timeZone = "America/Chicago";
  environment.systemPackages = with pkgs; [
    git
    neovim
  ];
  services.openssh.enable = true;
  system.stateVersion = "22.11";
  home-manager.users.chris = {pkgs, ...}: {
    home.stateVersion = "22.11";
  };
}
