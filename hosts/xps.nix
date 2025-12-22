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
    ./hardware-configurations/xps.nix
    inputs.agenix.nixosModules.default
    inputs.nixos-hardware.nixosModules.dell-xps-13-9310
    inputs.nixos-hardware.nixosModules.common-cpu-intel
    inputs.nixos-hardware.nixosModules.common-pc-ssd
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
    dotfiles.ghostty.enable = true;
    dotfiles.ghostty.service.enable = true;
    programs.helix.terminal.flavor = "wezterm";
    dotfiles.helix-terminal-tools = {
      enable = true;
      yazi = {
        enable = true;
        pickerWidth = 30;
        pickerSide = "left";
        helixKeybinding = "space.t.f"; # Toggle file picker
      };
    };
    programs.opencode.enable = true;
    programs.meganz.enable = true;
    programs.waybar.enable = false;

    # Ensure DBus uses the Nix-provided GTK portal backend instead of any Flatpak-exported one.
    # This avoids activation timeouts by pointing directly to the store binary.
    home.file.".local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.gtk.service".text = ''
      [D-BUS Service]
      Name=org.freedesktop.impl.portal.desktop.gtk
      Exec=${pkgs.xdg-desktop-portal-gtk}/libexec/xdg-desktop-portal-gtk
    '';

    # Import critical session env vars into user systemd and DBus, so DBus-activated
    # portal backends (gtk, etc.) inherit DISPLAY/WAYLAND env and don't hang.
    systemd.user.services."xdg-portal-env-import" = {
      Unit = {
        Description = "Import DISPLAY/WAYLAND env into user systemd and DBus";
        PartOf = ["graphical-session.target"];
        After = ["graphical-session.target"];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.dbus}/bin/dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE";
      };
      Install = {WantedBy = ["graphical-session.target"];};
    };

    # Pre-start the portal backends so the aggregator doesn't have to DBus-activate them
    # (works around DBus activation env issues).
    systemd.user.services."xdg-desktop-portal-gtk" = {
      Unit = {
        Description = "GTK xdg-desktop-portal backend";
        PartOf = ["graphical-session.target"];
        After = ["xdg-portal-env-import.service" "graphical-session.target"];
      };
      Service = {
        ExecStart = "${pkgs.xdg-desktop-portal-gtk}/libexec/xdg-desktop-portal-gtk";
        Restart = "on-failure";
      };
      Install = {WantedBy = ["graphical-session.target"];};
    };

    systemd.user.services."xdg-desktop-portal-cosmic" = {
      Unit = {
        Description = "COSMIC xdg-desktop-portal backend";
        PartOf = ["graphical-session.target"];
        After = ["xdg-portal-env-import.service" "graphical-session.target"];
      };
      Service = {
        ExecStart = "${pkgs.xdg-desktop-portal-cosmic}/libexec/xdg-desktop-portal-cosmic";
        Restart = "on-failure";
      };
      Install = {WantedBy = ["graphical-session.target"];};
    };
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
