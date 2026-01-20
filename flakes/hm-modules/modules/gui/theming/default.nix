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
    # GTK Theme
    gtk = {
      enable = true;
      theme = {
        name = "rose-pine-moon";
        package = pkgs.rose-pine-gtk-theme;
      };
      iconTheme = {
        name = "Papirus-Dark";
        package = pkgs.papirus-icon-theme;
      };
      cursorTheme = {
        name = "Bibata-Modern-Classic";
        package = pkgs.bibata-cursors;
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
      platformTheme.name = "gtk";
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
      name = "Bibata-Modern-Classic";
      package = pkgs.bibata-cursors;
      size = 24;
      gtk.enable = true;
      x11.enable = true;
    };

    # Environment variables for consistent theming
    home.sessionVariables = {
      GTK_THEME = "rose-pine-moon";
      QT_QPA_PLATFORMTHEME = "gtk2";
    };

    # Required packages
    home.packages = [
      pkgs.libsForQt5.qtstyleplugin-kvantum
      pkgs.qt6Packages.qtstyleplugin-kvantum
    ];
  };
}
