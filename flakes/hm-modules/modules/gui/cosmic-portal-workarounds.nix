# Workarounds for xdg-desktop-portal issues with COSMIC desktop
# This module ensures DBus-activated portal backends inherit the correct
# environment variables and don't hang during activation.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.gui.cosmic-portal-workarounds;
in {
  options.dotfiles.gui.cosmic-portal-workarounds = {
    enable = lib.mkEnableOption "COSMIC xdg-desktop-portal workarounds";
  };

  config = lib.mkIf cfg.enable {
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
}
