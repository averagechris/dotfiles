{ config, pkgs, lib, ... }:

{
  imports = [
    ./kanshi.nix
    ./keybindings.nix
    ./screenshots.nix
    ./waybar.nix
  ];

  config.wayland.windowManager.sway = {
    enable = true;
    config.bars = [ ];
    config.floating.criteria = [{ class = "Pavucontrol"; }];
    config.floating.titlebar = true;
    config.focus.mouseWarping = true;
    config.gaps.inner = 3;
    config.gaps.outer = 3;
    config.gaps.smartGaps = true;
    config.input."*".natural_scroll = "enabled";
    config.input."type:touchpad".tap = "enabled";
    config.workspaceAutoBackAndForth = true;
    wrapperFeatures.base = true;
    wrapperFeatures.gtk = true;
    extraSessionCommands = ''
      export MOZ_ENABLE_WAYLAND=1
      export MOZ_DBUS_REMOTE=1
    '';
  };

  # notifications daemon
  config.programs.mako = {
    enable = true;
    anchor = "top-center";
    defaultTimeout = 2750;
  };

  config.services.blueman-applet.enable = true;
  config.services.redshift = {
    enable = true;
    package = pkgs.redshift-wlr;
    latitude = "36.174465";
    longitude = "-86.767960";
  };

  config.home.packages = with pkgs; [
    imv
    libnotify
    mpv
    pavucontrol
    playerctl
    pulseaudio
    ranger
    source-code-pro
    swaylock-effects
    wl-clipboard
  ];

  config.xdg.configFile."nwg-panel/drawer.css".source = ./nwg-panel.css;
  config.xdg.configFile."nwg-bar/style.css".source = ./nwg-bar.css;
  config.xdg.configFile."nwg-bar/icons".source = ./icons;
  config.xdg.configFile."nwg-bar/bar.json".text = ''
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
  config.xdg.configFile."swaylock/config".source = ./swaylock.config;
  # config.xdg.configFile."wofi/config".text = ''
  #   term alacritty
  #   lines 5
  # '';
  config.xdg.configFile."wofi/style.css".text = ''
    window {
      background-color: rgba(--wofi-rgb-color0,1);
      font-family: iosevka;
      transition: 1s ease-in-out;
    }
    #input image {
      color: rgba(0,0,0,0)
    }
    #input {
      margin-bottom: 20px;
      margin-left: 100px;
      margin-right: 100px;
      margin-top: 10px;
      box-shadow: none;
      background-color: --wofi-color0;
      border: 5px solid --wofi-color3;
      border-radius: 0px;
      transition: 0.5s ease-in-out;
    }
    #input:focus {
      background-color: rgba(--wofi-rgb-color4,0.2);
      margin-left: 10px;
      margin-right: 10px;
      transition: 0.5s ease-in-out;
    }
    label {
      color: --wofi-color13;
      transition: 0.5s ease-in-out;
    }
    #outer-box {
      border: 5px solid --wofi-color2;
      transition: 0.5s ease-in-out;
    }
  '';
}
