{
  lib,
  config,
  pkgs,
  ...
}: {
  options.dotfiles.hyprland-desktop = {
    enable = lib.mkEnableOption "Hyprland desktop environment";
  };

  config = lib.mkIf config.dotfiles.hyprland-desktop.enable {
    # Enable Hyprland
    programs.hyprland = {
      enable = true;
      xwayland.enable = true;
    };

    # XDG portal for screen sharing, file dialogs
    xdg.portal = {
      enable = true;
      extraPortals = [
        pkgs.xdg-desktop-portal-hyprland
        pkgs.xdg-desktop-portal-gtk
      ];
      config.common.default = ["hyprland" "gtk"];
    };

    # Polkit for privilege escalation dialogs
    security.polkit.enable = true;
    systemd.user.services.polkit-gnome-authentication-agent-1 = {
      description = "polkit-gnome-authentication-agent-1";
      wantedBy = ["graphical-session.target"];
      wants = ["graphical-session.target"];
      after = ["graphical-session.target"];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
        Restart = "on-failure";
        RestartSec = 1;
        TimeoutStopSec = 10;
      };
    };

    # Fonts
    fonts.enableDefaultPackages = true;
    fonts.packages = with pkgs; [
      inter
      nerd-fonts.jetbrains-mono
      nerd-fonts.fira-code
      font-awesome
      noto-fonts
      noto-fonts-color-emoji
    ];

    # Essential services
    services.dbus.enable = true;
    services.gvfs.enable = true; # For Nautilus trash, mounts
    services.udisks2.enable = true; # USB automount
    services.upower.enable = true; # Battery info for Eww

    # Greetd login manager with tuigreet
    services.greetd = {
      enable = true;
      settings.default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd Hyprland";
        user = "greeter";
      };
    };

    # System packages needed for Hyprland desktop
    environment.systemPackages = with pkgs; [
      wl-clipboard
      wdisplays # Monitor configuration GUI
      brightnessctl
      playerctl
      pamixer
      libnotify
    ];
  };
}
