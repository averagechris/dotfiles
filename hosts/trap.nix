{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    ../nixpkgs/nixos/common.nix
    ../nixpkgs/nixos/desktop_common.nix
    ../nixpkgs/nixos/docker.nix
    ../nixpkgs/nixos/graphical.nix
    ../nixpkgs/nixos/greetd.nix
    ../nixpkgs/nixos/networking.nix
    ../nixpkgs/nixos/sound.nix
    ../nixpkgs/nixos/tailscale.nix
    ../nixpkgs/nixos/users/chris.nix
    ./hardware-configurations/trap.nix
    inputs.agenix.nixosModules.default
    inputs.nixos-hardware.nixosModules.system76
    inputs.nixos-hardware.nixosModules.common-cpu-amd
    inputs.nixos-hardware.nixosModules.common-cpu-amd-pstate
    inputs.nixos-hardware.nixosModules.common-pc-ssd
  ];

  boot.initrd.luks.devices = {
    root.device = "/dev/nvme1n1p2";
    root.preLVM = true;
  };
  networking.hostName = "trap";

  hardware.opengl.enable = true;
  hardware.opengl.driSupport = true;
  hardware.enableRedistributableFirmware = true;
  hardware.system76.enableAll = true;
  environment.systemPackages = [pkgs.system76-firmware];
  system.stateVersion = "23.05";
  home-manager.users.chris = {pkgs, ...}: {
    home.stateVersion = "23.05";
    dotfiles.gui.enable = true;
    dotfiles.shell.python.enable = true;
    programs.meganz.enable = true;
    wayland.windowManager.sway.config.input."type:touchpad" = {
      tap = "disabled";
      click_method = "button_areas";
    };
  };

  services.dbus.enable = true;
  xdg.portal = {
    enable = true;
    wlr.enable = true;
    # gtk portal needed to make gtk apps happy
    extraPortals = [pkgs.xdg-desktop-portal-gtk];
  };

  fonts.enableDefaultPackages = true;
  fonts.packages = with pkgs; [dejavu_fonts font-awesome nerdfonts];
}
