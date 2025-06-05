{
  config,
  dotfiles_lib,
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
    waybar.enable = dotfiles_lib.options.mkDefaultEnabledOption "Enable waybar with hyprland config";
  };

  imports = [
    ../sway/screenshots.nix
    ../sway/swayidle.nix
    ./windowrules.nix
    ./waybar.nix
    ./wallpaperd.nix
  ];

  config = lib.mkIf cfg.enable {
    dotfiles.gui.swayidle.enable = lib.mkDefault true;
    wayland.windowManager.hyprland = {
      inherit (cfg) enable;
      xwayland.enable = true;
      systemd.enable = true;
      plugins = [];
      settings = {
        env = [
          "GDK_BACKEND,wayland"
          "XCURSOR_SIZE,24"
        ];
        exec-once = [
          "${pkgs.signal-desktop}/bin/signal-desktop"
          "${pkgs.firefox}/bin/firefox"
        ];
        monitor = [
          ",preferred,auto,auto"
        ];
        input = {
          kb_layout = "us, us";
          kb_variant = "colemak_dh, basic";
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
          # cursor_inactive_timeout = 5;
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
          # drop_shadow = "yes";
          # shadow_range = 4;
          # shadow_render_power = 3;
          # "col.shadow" = "rgba(1a1a1aee)";
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
        # master = {
        #   new_is_master = true;
        # };
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
          brightctl = "${pkgs.brightnessctl}/bin/brightnessctl";
          pamixer = "${pkgs.pamixer}/bin/pamixer";
          playerctl = "${pkgs.playerctl}/bin/playerctl";
          term = config.dotfiles.gui.terminal.binPath;
          withSuper = with lib.strings;
            lst: (map (rule:
              if (hasPrefix "+" rule)
              then "$mainMod ${rule}"
              else "$mainMod, ${rule}")
            lst);
        in
          [
            ",XF86AudioRaiseVolume, exec, ${pamixer} --increase 5"
            ",XF86AudioLowerVolume, exec, ${pamixer} --decrease 5"
            "SHIFT,XF86AudioRaiseVolume, exec, ${pamixer} --increase 5"
            "SHIFT,XF86AudioLowerVolume, exec, ${pamixer} --decrease 5"
            ",XF86AudioMute, exec, ${pamixer} --toggle-mute"
            ",XF86AudioNext, exec, ${playerctl} next"
            ",XF86AudioPrev, exec, ${playerctl} previous"
            ",XF86AudioStop, exec, ${playerctl} play-pause"
            ",XF86MonBrightnessUp, exec, ${brightctl} set +5%"
            ",XF86MonBrightnessDown, exec, ${brightctl} set 5%-"
          ]
          ++ withSuper [
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
            "m, movefocus, l"
            "n, movefocus, d"
            "e, movefocus, u"
            "i, movefocus, r"

            "+ SHIFT, m, swapwindow, l"
            "+ SHIFT, n, swapwindow, d"
            "+ SHIFT, e, swapwindow, u"
            "+ SHIFT, i, swapwindow, r"

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
            "+SHIFT, i, workspace, e+1"
            "+SHIFT, m, workspace, e-1"

            # Scroll through existing workspaces with mainMod + scroll
            "mouse_right, workspace, e+1"
            "mouse_left, workspace, e-1"

            # Move window to scratch pad
            "+SHIFT, $dashKey, movetoworkspacesilent, special:scratchpad"
            "$dashKey, togglespecialworkspace, scratchpad"

            # toggle between qwerty and colemak_dh keyboard layouts
            "+ SHIFT + CTRL + ALT, SPACE, exec, hyprctl switchxkblayout at-translated-set-2-keyboard next"
          ];
        bindl = [
          ",switch:Lid Switch, exec, ${toggleDisplayWithLid}"
        ];
        bindm = [
          # Move/resize windows with mainMod + LMB/RMB and dragging
          "$mainMod, mouse:272, movewindow"
          "$mainMod, mouse:273, resizewindow"
        ];
        binds = {
          workspace_back_and_forth = true;
          scroll_event_delay = 100;
        };
      };
      extraConfig = ''
        device {
          name = at-translated-set-2-keyboard
          kb_layout = us, us
          kb_variant = colemak_dh, basic
          resolve_binds_by_sym = 1
        }

        device {
          name = dygma-defy-keyboard
          kb_layout = us
          kb_variant = basic
          resolve_binds_by_sym = 1
        }
      '';
    };

    programs.wallpaperd = with lib; {
      enable = mkDefault true;
      enableHyprlandIntegration = mkDefault true;
    };

    # notifications daemon
    services.mako = {
      enable = lib.mkDefault true;
      settings.anchor = lib.mkDefault "top-center";
      settings.defaultTimeout = lib.mkDefault 2750;
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
      swaylock-effects
      wl-clipboard
      wofi
    ];
  };
}
