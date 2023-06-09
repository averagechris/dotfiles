{
  config,
  pkgs,
  lib,
  ...
}: let
  dotfiles_cfg = config.dotfiles;
  cfg = dotfiles_cfg.gui.sway;
in
  with lib; {
    imports = [
      ./kanshi.nix
      ./keybindings.nix
      ./screenshots.nix
      ./waybar.nix
      ./swayidle.nix
      ./sway.nix
    ];

    options.dotfiles.gui.sway = {
      enable = mkEnableOption "Use highly configured sway as the window manager.";
      idle.enable = mkEnableOption "Use my configured swayidle or not.";
    };

    config = mkIf cfg.enable {
      wayland.windowManager.sway = {
        enable = mkDefault cfg.enable;
        config.terminal = dotfiles_cfg.gui.terminal;
      };
      programs.waybar.enable = mkDefault cfg.enable;
      services.kanshi.enable = mkDefault cfg.enable;

      # notifications daemon
      services.mako = {
        enable = mkDefault true;
        anchor = "top-center";
        defaultTimeout = 2750;
      };

      services.blueman-applet.enable = mkDefault true;
      services.gammastep = {
        enable = mkDefault true;
        latitude = "36.174465";
        longitude = "-86.767960";
      };

      home.packages = with pkgs; [
        wldash
        imv
        libnotify
        mpv
        pavucontrol
        playerctl
        pulseaudio
        ranger
        swaylock-effects
        wl-clipboard
      ];

      xdg.configFile."nwg-panel/drawer.css".source = ./nwg-panel.css;
      xdg.configFile."nwg-bar/style.css".source = ./nwg-bar.css;
      xdg.configFile."nwg-bar/icons".source = ./icons;
      xdg.configFile."nwg-bar/bar.json".text = ''
        [
          {
            "label": "Lock screen",
            "exec": "${pkgs.swaylock-effects}/bin/swaylock -f -c 000000",
            "icon": "${config.xdg.configHome}/nwg-bar/icons/system-lock-screen.svg"
          },
          {
            "label": "Sleep",
            "exec": "systemctl hybrid-sleep",
            "icon": "${config.xdg.configHome}/nwg-bar/icons/system-shutdown.svg"
          },
          {
            "label": "Logout",
            "exec": "swaymsg exit",
            "icon": "${config.xdg.configHome}/nwg-bar/icons/system-log-out.svg"
          },
          {
            "label": "Reboot",
            "exec": "systemctl reboot",
            "icon": "${config.xdg.configHome}/nwg-bar/icons/system-reboot.svg"
          },
          {
            "label": "Shutdown",
            "exec": "systemctl -i poweroff",
            "icon": "${config.xdg.configHome}/nwg-bar/icons/system-shutdown.svg"
          }
        ]
      '';
      xdg.configFile."swaylock/config".source = ./swaylock.config;
    };
  }
