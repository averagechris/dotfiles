{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    ../nixpkgs/nixos/common.nix
    ../nixpkgs/nixos/desktop_common.nix
    ../nixpkgs/nixos/docker.nix
    # ../nixpkgs/nixos/graphical.nix
    # ../nixpkgs/nixos/greetd.nix
    ../nixpkgs/nixos/networking.nix
    ../nixpkgs/nixos/sound.nix
    ../nixpkgs/nixos/tailscale.nix
    ../nixpkgs/nixos/virtualization.nix
    ../nixpkgs/nixos/users/chris.nix
    ../nixpkgs/nixos/users/christiana.nix
    ./hardware-configurations/xps.nix
    inputs.agenix.nixosModules.default
    inputs.nixos-hardware.nixosModules.dell-xps-13-9310
    inputs.nixos-hardware.nixosModules.common-cpu-intel
    inputs.nixos-hardware.nixosModules.common-pc-ssd
    inputs.nixos-cosmic.nixosModules.default
  ];
  services.desktopManager.cosmic.enable = true;
  services.displayManager.cosmic-greeter.enable = true;
  environment.sessionVariables.COSMIC_DATA_CONTROL_ENABLED = 1;

  boot.initrd.luks.devices.root.device = "/dev/nvme0n1p2";
  networking.hostName = "cruber";

  networking.wireless.interfaces = ["wlp0s20f3"];
  networking.interfaces.wlp0s20f3.useDHCP = true;

  hardware.graphics.enable = true;
  hardware.enableRedistributableFirmware = true;
  system.stateVersion = "24.11";
  home-manager.users.christiana = {...}: {
    home.stateVersion = "24.11";
  };
  home-manager.users.chris = {...}: {
    home.stateVersion = "24.11";
    dotfiles.gui.enable = true;
    dotfiles.gui.sway.enable = false;
    dotfiles.gui.hyprland.enable = false;
    dotfiles.shell.python.enable = true;
    dotfiles.shell.pipx.enable = false;
    programs.obsidian.enable = false;
  };

  services.dbus.enable = true;
  services.flatpak.enable = true;
  services.fwupd.enable = true;

  users.users.chris.extraGroups = ["docker"];

  boot.kernelModules = [
    "ipt_dnat"
    "ipt_mark"
    "iptable_filter"
    "iptable_nat"
    "sch_cake"
    "xt_nat"
  ];
}
