{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ../nixpkgs/nixos/common.nix
    ../nixpkgs/nixos/desktop_common.nix
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
    inputs.nixos-cosmic.nixosModules.default
  ];

  services.desktopManager.cosmic.enable = true;
  services.displayManager.cosmic-greeter.enable = true;
  environment.sessionVariables.COSMIC_DATA_CONTROL_ENABLED = 1;
  services.gnome.gnome-keyring.enable = false;

  boot.initrd.luks.devices.root.device = "/dev/sda2";
  networking.hostName = "thorny";

  networking.wireless.interfaces = ["wlp6s0"];

  environment.systemPackages = with pkgs; [
    system76-firmware
    mesa
    cosmic-ext-tweaks
    cosmic-ext-ctl
    cosmic-ext-applet-emoji-selector
    cosmic-ext-applet-emoji-selector
    cosmic-ext-applet-external-monitor-brightness
    cosmic-ext-ctl
    examine
    cosmic-ext-tweaks
    system76-firmware
  ];
  hardware.graphics.enable = true;
  hardware.enableRedistributableFirmware = true;
  hardware.system76.enableAll = true;

  programs.steam.enable = true;
  hardware.xone.enable = true;

  system.stateVersion = "24.11";
  home-manager.users.chris = {...}: {
    home.stateVersion = "24.11";
    dotfiles.gui.enable = true;
    programs.meganz.enable = true;

    dotfiles.gui.sway.enable = false;
    dotfiles.gui.hyprland.enable = false;
    dotfiles.gui.swayidle.enable = false;
    dotfiles.shell.calibre-utils.enable = true;
    dotfiles.shell.python.enable = true;
    dotfiles.shell.pipx.enable = true;
    programs.obsidian.enable = false;
    dotfiles.shell.yazi.enable = true;
    dotfiles.wezterm.enable = true;
    programs.helix.terminal.flavor = "wezterm";
    dotfiles.helix-terminal-tools = {
      enable = true;
      yazi = {
        enable = true;
        pickerWidth = 30;
        pickerSide = "left";
        helixKeybinding = "space.t.f"; # Toggle file picker
      };
      claude = {
        enable = true;
      };
    };
    home.packages = [pkgs.claude-code];
  };

  services.dbus.enable = true;
  services.flatpak.enable = true;
  services.fwupd.enable = true;
}
