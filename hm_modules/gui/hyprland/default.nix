{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.dotfiles.gui.hyprland;
in {
  options.dotfiles.gui.hyprland = {
    enable = lib.mkEnableOption "Enable configured hyprland.";
  };

  imports = [
    ../sway/screenshots.nix
    ../sway/swayidle.nix
  ];

  config = lib.mkIf cfg.enable {
    wayland.windowManager.hyprland = {
      inherit (cfg) enable;
      xwayland.enable = true;
      systemdIntegration = true;
      plugins = [];
      settings = {
        env = [
          "GDK_BACKEND,wayland"
          "XCURSOR_SIZE,24"
        ];
        exec-once = [
          "firefox & signal"
        ];
        monitor = [
          ",preferred,auto,auto"
        ];
        input = {
          kb_layout = "us";
          follow_mouse = 1;
          natural_scroll = "yes";
          sensitivity = 0.0;
          numlock_by_default = true;
          touchpad = {
            natural_scroll = "yes";
            scroll_factor = 0.5;
            middle_button_emulation = true;
            clickfinger_behavior = true;
          };
        };
        general = {
          gaps_in = 3;
          gaps_out = 3;
          border_size = 1;
          "col.active_border" = "rgba(33ccffee) rgba(00ff99ee) 45deg";
          "col.inactive_border" = "rgba(595959aa)";
          cursor_inactive_timeout = 5;
          resize_on_border = true;
          layout = "dwindle";
        };
        decoration = {
          rounding = 5;
          blur = {
            enabled = true;
            size = 3;
            passes = 1;
          };
          active_opacity = 1.0;
          inactive_opacity = 0.9825;
          fullscreen_opacity = 1.0;
          dim_inactive = true;
          dim_strength = 0.25;
          drop_shadow = "yes";
          shadow_range = 4;
          shadow_render_power = 3;
          "col.shadow" = "rgba(1a1a1aee)";
        };
        animations = {
          enabled = "yes";
          bezier = ["windowBezier, 0.05, 0.9, 0.1, 1.05"];
          animation = [
            "windows, 1, 7, windowBezier"
            "windowsOut, 1, 7, default, popin 80%"
            "border, 1, 10, default"
            "borderangle, 1, 8, default"
            "fade, 1, 7, default"
            "workspaces, 1, 6, default"
          ];
        };
        dwindle = {
          pseudotile = "yes";
          preserve_split = "yes";
        };
        master = {
          new_is_master = true;
        };
        gestures = {
          workspace_swipe = "on";
        };
        misc = {
          animate_manual_resizes = true;
          disable_hyprland_logo = false;
          vrr = 2;
        };
        "$mainMod" = "SUPER";
        bind = let
          term = with config.dotfiles.gui; "${terminal}/bin/${terminal.pname}";
        in [
          "$mainMod, T, exec, ${term}"
          "$mainMod, R, exec, ${pkgs.wofi}/bin/wofi --show drun"
        ];
      };
      extraConfig = builtins.readFile ./hyprland.conf;
    };

    # programs.waybar.enable = lib.mkDefault cfg.enable;

    # notifications daemon
    services.mako = {
      enable = lib.mkDefault true;
      anchor = lib.mkDefault "top-center";
      defaultTimeout = lib.mkDefault 2750;
    };

    services.blueman-applet.enable = lib.mkDefault true;
    services.gammastep = {
      enable = lib.mkDefault true;
      latitude = "36.174465";
      longitude = "-86.767960";
    };

    home.packages = with pkgs; [
      imv
      libnotify
      mpv
      pavucontrol
      playerctl
      pulseaudio
      ranger
      swaylock-effects
      wl-clipboard
      wofi
    ];
  };
}
