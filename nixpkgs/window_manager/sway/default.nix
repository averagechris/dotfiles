{ config, pkgs, lib, ... }:

{
  imports = [
    ./keybindings.nix
    ./screenshots.nix
    ./waybar.nix
  ];

  config.wayland.windowManager.sway = {
    enable = true;
    config.bars = [];
    config.floating.criteria = [ { class = "Pavucontrol"; } ];
    config.floating.titlebar = true;
    config.gaps.inner = 3;
    config.gaps.outer = 3;
    config.gaps.smartGaps = true;
    config.input."*".natural_scroll = "enabled";
    config.input."touchpad".tap = "enabled";
    config.workspaceAutoBackAndForth = true;
    wrapperFeatures.base = true;
    wrapperFeatures.gtk = true;
    extraSessionCommands = ''
      export MOZ_ENABLE_WAYLAND=1
    '';
  };

  # notifications daemon
  config.programs.mako = {
    enable = true;
    anchor = "top-center";
    defaultTimeout = 2750;
  };

  config.services.blueman-applet.enable = true;

  config.home.packages = with pkgs; [
    swaylock-effects
    source-code-pro
    libnotify
    mpv
    imv
    pavucontrol
    playerctl
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
        "label": "Logout",
        "exec": "swaynag -t warning -m 'close sway and wayland?' -b 'yes' 'swaymsg exit'",
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
}
