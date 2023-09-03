{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.dotfiles.gui.hyprland;
  toggleDisplayWithLid = let
    name = "disable-builtin-display-when-lid-closed";
    script = pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [pkgs.coreutils];
      text = ''
        if grep open /proc/acpi/button/lid/LID0/state; then
            hyprctl keyword monitor "eDP-1,preferred,auto,auto"
        else
            if [[ "$(hyprctl monitors | grep -c Monitor)" != "1" ]]; then
                hyprctl keyword monitor "eDP-1,disable"
            fi
        fi
      '';
    };
  in "${script}/bin/${name}";
in {
  options.dotfiles.gui.hyprland = {
    enable = lib.mkEnableOption "Enable configured hyprland.";
  };

  imports = [
    ../sway/screenshots.nix
    ../sway/swayidle.nix
    ./windowrules.nix
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
          "${pkgs.firefox}/bin/firefox & ${pkgs.signal-desktop}/bin/signal-desktop"
        ];
        monitor = [
          "DP-11,preferred,0x0,1,transform,3"
          "DP-9,highres,auto,1"
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
        "$dashKey" = 20; # the literal - key

        bind = let
          term = with config.dotfiles.gui; "${terminal}/bin/${terminal.pname}";
          withSuper = with lib.strings;
            lst: (map (rule:
              if (hasPrefix "+" rule)
              then "$mainMod ${rule}"
              else "$mainMod, ${rule}")
            lst);
        in
          withSuper [
            # primary actions
            "T, exec, ${term}"
            "Q, killactive,"
            "+SHIFT, Q, exit,"
            "+SHIFT, F, togglefloating,"
            "F, fullscreen,"
            # "P, pseudo,"
            # "J, togglesplit,"
            "P, togglefloating"
            "P, pin"
            "SPACE, exec, ${pkgs.wofi}/bin/wofi --show drun"

            # movement between windows
            "h, movefocus, l"
            "j, movefocus, d"
            "k, movefocus, u"
            "l, movefocus, r"

            "+ SHIFT, h, swapwindow, l"
            "+ SHIFT, j, swapwindow, d"
            "+ SHIFT, k, swapwindow, u"
            "+ SHIFT, l, swapwindow, r"

            # Move active window to a workspace with mainMod + SHIFT + [0-9]
            "+ SHIFT, 1, movetoworkspace, 1"
            "+ SHIFT, 2, movetoworkspace, 2"
            "+ SHIFT, 3, movetoworkspace, 3"
            "+ SHIFT, 4, movetoworkspace, 4"
            "+ SHIFT, 5, movetoworkspace, 5"
            "+ SHIFT, 6, movetoworkspace, 6"
            "+ SHIFT, 7, movetoworkspace, 7"
            "+ SHIFT, 8, movetoworkspace, 8"
            "+ SHIFT, 9, movetoworkspace, 9"
            "+ SHIFT, 0, movetoworkspace, 10"

            # change to workspace by number
            "1, workspace, 1"
            "2, workspace, 2"
            "3, workspace, 3"
            "4, workspace, 4"
            "5, workspace, 5"
            "6, workspace, 6"
            "7, workspace, 7"
            "8, workspace, 8"
            "9, workspace, 9"
            "0, workspace, 10"

            # Scroll through existing workspaces with mainMod + scroll
            "mouse_down, workspace, e+1"
            "mouse_up, workspace, e-1"

            # Move window to scratch pad
            "+SHIFT, $dashKey, movetoworkspacesilent, special:scratchpad"
            "$dashKey, togglespecialworkspace, scratchpad"
          ];
        bindl = [
          ",switch:Lid Switch, exec, ${toggleDisplayWithLid}"
        ];
        bindm = [
          # Move/resize windows with mainMod + LMB/RMB and dragging
          "$mainMod, mouse:272, movewindow"
          "$mainMod, mouse:273, resizewindow"
        ];
      };
      # extraConfig = ''
      #   exec=touch ~/.config/hypr/scratch_config.conf
      #   source=~/.config/hypr/scratch_config.conf
      # '';
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
