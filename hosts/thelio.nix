{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ../nixpkgs/nixos/common.nix
    ../nixpkgs/nixos/desktop_common.nix
    ../nixpkgs/nixos/graphical.nix
    ../nixpkgs/nixos/greetd.nix
    ../nixpkgs/nixos/networking.nix
    ../nixpkgs/nixos/docker.nix
    ../nixpkgs/nixos/sound.nix
    ../nixpkgs/nixos/tailscale.nix
    ../nixpkgs/nixos/users/chris.nix
    ./hardware-configurations/thelio.nix
    inputs.agenix.nixosModules.default
    inputs.nixos-hardware.nixosModules.system76
    inputs.nixos-hardware.nixosModules.common-cpu-amd
    inputs.nixos-hardware.nixosModules.common-gpu-amd
    inputs.nixos-hardware.nixosModules.common-cpu-amd-pstate
    inputs.nixos-hardware.nixosModules.common-pc-ssd
  ];

  boot.initrd.luks.devices.root.device = "/dev/sda2";
  networking.hostName = "thelio-nixos";

  networking.wireless.interfaces = ["wlp6s0"];

  environment.systemPackages = with pkgs; [system76-firmware];
  hardware.opengl.enable = true;
  hardware.enableRedistributableFirmware = true;
  hardware.system76.enableAll = true;
  programs.steam.enable = true;

  system.stateVersion = "21.05";
  home-manager.users.chris = {pkgs, ...}: {
    home.stateVersion = "21.05";
    dotfiles.gui.enable = true;
    programs.meganz.enable = true;

    dotfiles.gui.sway.enable = false;
    dotfiles.gui.hyprland.enable = true;
    dotfiles.gui.swayidle.enable = false;
    dotfiles.shell.python.enable = true;
    dotfiles.shell.pipx.enable = true;
    programs.obsidian.enable = false;
    programs.helix.package = inputs.helix.packages.x86_64-linux.default;

    home.packages = [pkgs.trayscale];
  };
  services.dbus.enable = true;
  services.flatpak.enable = true;
  services.fwupd.enable = true;

  xdg.portal = {
    enable = true;
    wlr.enable = true;
    # gtk portal needed to make gtk apps happy
    extraPortals = [pkgs.xdg-desktop-portal-gtk];
  };

  fonts.enableDefaultPackages = true;
  fonts.packages = with pkgs; [dejavu_fonts font-awesome nerdfonts];
}
