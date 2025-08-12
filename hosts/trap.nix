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
    ../nixpkgs/nixos/networking.nix
    ../nixpkgs/nixos/sound.nix
    ../nixpkgs/nixos/tailscale.nix
    ../nixpkgs/nixos/virtualization.nix
    ../nixpkgs/nixos/users/chris.nix
    ./hardware-configurations/trap.nix
    inputs.agenix.nixosModules.default
    inputs.nixos-hardware.nixosModules.system76
    inputs.nixos-hardware.nixosModules.common-cpu-amd
    inputs.nixos-hardware.nixosModules.common-cpu-amd-pstate
    inputs.nixos-hardware.nixosModules.common-pc-ssd
  ];

  services.desktopManager.cosmic.enable = true;
  services.displayManager.cosmic-greeter.enable = true;
  environment.sessionVariables.COSMIC_DATA_CONTROL_ENABLED = 1;
  environment.systemPackages = with pkgs; [
    cosmic-ext-ctl
    cosmic-ext-tweaks
    examine
    system76-firmware
  ];

  boot.initrd.luks.devices = {
    root.device = "/dev/nvme1n1p2";
    root.preLVM = true;
  };
  networking.hostName = "trap";

  hardware.graphics.enable = true;
  hardware.enableRedistributableFirmware = true;
  hardware.system76.enableAll = true;
  system.stateVersion = "23.05";
  home-manager.users.chris = {...}: {
    home.stateVersion = "23.05";
    dotfiles.gui.enable = true;
    dotfiles.gui.sway.enable = false;
    dotfiles.gui.hyprland.enable = false;
    dotfiles.gui.swayidle.enable = false;
    dotfiles.shell.calibre-utils.enable = true;
    dotfiles.shell.python.enable = true;
    dotfiles.shell.pipx.enable = true;
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
    programs.jujutsu.enable = true;
    programs.meganz.enable = true;
    programs.waybar.enable = false;
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
  fonts.packages = with pkgs; [dejavu_fonts font-awesome nerd-fonts.droid-sans-mono nerd-fonts.fira-code];

  users.users.chris.extraGroups = ["docker"];
}
