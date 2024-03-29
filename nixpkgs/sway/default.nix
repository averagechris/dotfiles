{
  config,
  pkgs,
  lib,
  ...
}: let
  wallpapers = "${config.home.homeDirectory}/dotfiles/nixpkgs/sway/wallpapers";
in {
  imports = [
    ./kanshi.nix
    ./keybindings.nix
    ./screenshots.nix
    ./waybar.nix
    ./swayidle.nix
  ];

  config.wayland.windowManager.sway = {
    enable = true;
    config.bars = [];
    config.floating.criteria = [
      {app_id = "pavucontrol";}
      {app_id = "zenity";}
      {class = ".zoom";}
    ];
    config.floating.titlebar = true;
    config.focus.mouseWarping = true;
    config.gaps.inner = 3;
    config.gaps.outer = 3;
    config.gaps.smartGaps = true;
    config.input."*".natural_scroll = "enabled";
    config.input."type:touchpad".tap = "enabled";
    config.output."*".bg = "${wallpapers}/1.jpg fill";
    config.startup = [];
    config.workspaceAutoBackAndForth = true;
    wrapperFeatures.base = true;
    wrapperFeatures.gtk = true;
    extraSessionCommands = ''
      export MOZ_ENABLE_WAYLAND=1
      export MOZ_DBUS_REMOTE=1
    '';
    extraConfig = ''
      seat seat0 xcursor_theme breeze 62
      for_window [app_id="scratch_terminal"] move scratchpad, resize set 800 610
      exec ${pkgs.alacritty}/bin/alacritty --title=scratch_terminal
    '';
  };

  # notifications daemon
  config.programs.mako = {
    enable = true;
    anchor = "top-center";
    defaultTimeout = 2750;
  };

  config.services.blueman-applet.enable = true;
  config.services.gammastep = {
    enable = true;
    latitude = "36.174465";
    longitude = "-86.767960";
  };

  config.home.packages = with pkgs; [
    wldash
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
}
