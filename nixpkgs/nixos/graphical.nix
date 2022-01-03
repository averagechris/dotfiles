{ config, pkgs, lib, ... }:

{
  environment.systemPackages = with pkgs; [
    breeze-gtk
    breeze-icons
    breeze-qt5
  ];

  environment.extraInit = ''
    # GTK3: add theme to search path for themes
    export XDG_DATA_DIRS="${pkgs.breeze-gtk}/share:$XDG_DATA_DIRS"
    # GTK3: add /etc/xdg/gtk-3.0 to search path for settings.ini
    export XDG_CONFIG_DIRS="/etc/xdg:$XDG_CONFIG_DIRS"
    # GTK2 theme + icon theme
    export GTK2_RC_FILES=${pkgs.writeText "iconrc" ''gtk-icon-theme-name="breeze"''}:$GTK2_RC_FILES
    # QT theme
    export QT_STYLE_OVERRIDE=breeze
  '';

  environment.etc."xdg/gtk-3.0/settings.ini" = {
    text = ''
      [Settings]
      gtk-icon-theme-name=breeze
      gtk-theme-name=Breeze-Dark
      gtk-application-prefer-dark-theme = true
    '';
    mode = "444";
  };

  environment.etc."gtk-2.0/gtkrc" = {
    text = ''
      gtk-icon-theme-name=breezewwweeew
    '';
    mode = "444";
  };
}
