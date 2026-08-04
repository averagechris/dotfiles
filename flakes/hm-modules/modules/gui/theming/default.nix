# GTK/Qt theming with Rose Pine Moon
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.theming;
in {
  options.dotfiles.theming = {
    enable = lib.mkEnableOption "Rose Pine Moon theming for GTK/Qt";
  };

  config = lib.mkIf cfg.enable {
    # GTK Theme. GTK 2 is deliberately unsupported by the local modern-only
    # package, so configure each supported toolkit generation explicitly.
    gtk = {
      enable = true;
      gtk2.enable = false;
      gtk3.theme = {
        name = "rose-pine-moon";
        package = pkgs.rose-pine-gtk-modern;
      };
      gtk4.theme = {
        name = "rose-pine-moon";
        package = pkgs.rose-pine-gtk-modern;
      };
      iconTheme = {
        name = "Papirus-Dark";
        package = pkgs.papirus-icon-theme;
      };
      cursorTheme = {
        name = "capitaine-cursors";
        package = pkgs.capitaine-cursors;
        size = 24;
      };
      font = {
        name = "Inter";
        size = 11;
      };
      gtk3.extraConfig = {
        gtk-application-prefer-dark-theme = true;
      };
      gtk4.extraConfig = {
        gtk-application-prefer-dark-theme = true;
      };
    };

    # Qt Theme
    qt = {
      enable = true;
      platformTheme.name = "gtk3";
      style = {
        name = "kvantum";
      };
    };

    # Kvantum theme configuration
    xdg.configFile."Kvantum/kvantum.kvconfig".text = ''
      [General]
      theme=RosePineMoonDark
    '';

    # Cursor theme for Wayland
    home.pointerCursor = {
      name = "capitaine-cursors";
      package = pkgs.capitaine-cursors;
      size = 24;
      gtk.enable = true;
      x11.enable = true;
    };

    # Environment variables for consistent theming
    home.sessionVariables = {
      GTK_THEME = "rose-pine-moon";
    };

    # Required packages
    home.packages = [
      pkgs.libsForQt5.qtstyleplugin-kvantum
      pkgs.qt6Packages.qtstyleplugin-kvantum
    ];
  };
}
