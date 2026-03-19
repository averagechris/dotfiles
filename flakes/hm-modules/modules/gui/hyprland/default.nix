{
  config,
  dotfiles_lib,
  pkgs,
  lib,
  ...
}: let
  cfg = config.dotfiles.gui.hyprland;
  term = config.dotfiles.gui.terminal.binPath;
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
    ../wayland-shared/screenshots.nix
    ../wayland-shared/swayidle.nix
    ./windowrules.nix
    ./waybar.nix
    ./wallpaperd.nix
    ./theme.nix
    ./animations.nix
    ./gestures.nix
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
          "XDG_DATA_DIRS,${config.home.homeDirectory}/.nix-profile/share:${config.home.profileDirectory}/share:/nix/var/nix/profiles/default/share:/run/current-system/sw/share"
          "XCURSOR_SIZE,24"
          "HYPRCURSOR_SIZE,24"
        ];
        exec-once = [
          "${pkgs.signal-desktop}/bin/signal-desktop --start-in-tray"
          "anyrun daemon"
          "hyprpaper"
          "hyprsunset -t 4500"
          # Zen browser and Telegram are installed via nix profile
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
          gaps_in = 4;
          gaps_out = 6;
          border_size = 2;
          "col.active_border" = "rgba(c4a7e7ee) rgba(9ccfd8ee) 45deg";
          "col.inactive_border" = "rgba(393552aa)";
          resize_on_border = true;
          layout = "dwindle";
        };
        decoration = {
          rounding = 8;
          blur = {
            enabled = true;
            size = 4;
            passes = 2;
            new_optimizations = true;
            xray = false;
          };
          active_opacity = 1.0;
          inactive_opacity = 0.95;
          fullscreen_opacity = 1.0;
          dim_inactive = true;
          dim_strength = 0.15;
          shadow = {
            enabled = true;
            range = 8;
            render_power = 2;
            color = "rgba(1a1a1aee)";
          };
        };

        dwindle = {
          pseudotile = true;
          preserve_split = true;
          smart_split = true;
          smart_resizing = true;
        };
        # master = {
        #   new_is_master = true;
        # };
        misc = {
          disable_hyprland_logo = true;
          disable_splash_rendering = true;
          vrr = 1;
          mouse_move_enables_dpms = true;
          key_press_enables_dpms = true;
          animate_manual_resizes = true;
          animate_mouse_windowdragging = true;
        };
        "$mainMod" = "SUPER";
        "$dashKey" = 20; # the literal - key

        bind = let
          brightctl = "${pkgs.brightnessctl}/bin/brightnessctl";
          pamixer = "${pkgs.pamixer}/bin/pamixer";
          playerctl = "${pkgs.playerctl}/bin/playerctl";
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
            "+SHIFT, P, pin"
            "SPACE, exec, anyrun"

            # movement between windows
            "m, movefocus, l"
            "n, movefocus, d"
            "e, movefocus, u"
            "i, movefocus, r"

            "+SHIFT, m, swapwindow, l"
            "+SHIFT, n, swapwindow, d"
            "+SHIFT, e, swapwindow, u"
            "+SHIFT, i, swapwindow, r"

            # Move active window to a workspace with mainMod + SHIFT + [0-9]
            "+SHIFT, 1, movetoworkspace, 1"
            "+SHIFT, 2, movetoworkspace, 2"
            "+SHIFT, 3, movetoworkspace, 3"
            "+SHIFT, 4, movetoworkspace, 4"
            "+SHIFT, 5, movetoworkspace, 5"
            "+SHIFT, 6, movetoworkspace, 6"
            "+SHIFT, 7, movetoworkspace, 7"
            "+SHIFT, 8, movetoworkspace, 8"
            "+SHIFT, 9, movetoworkspace, 9"
            "+SHIFT, 0, movetoworkspace, 10"

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
            "+ALT, m, workspace, e-1"
            "+ALT, i, workspace, e+1"

            # Scroll through existing workspaces with mainMod + scroll
            "mouse_right, workspace, e+1"
            "mouse_left, workspace, e-1"

            # Terminal scratchpad (grave/backtick key)
            "grave, togglespecialworkspace, terminal"
            "+SHIFT, grave, movetoworkspacesilent, special:terminal"

            # Scratchpad submap launcher
            "s, submap, scratchpad"

            # Resize submap launcher
            "r, submap, resize"

            # Quick actions submap launcher
            "a, submap, quickactions"

            # toggle between qwerty and colemak_dh keyboard layouts (mega keychord)
            "+SHIFT+CTRL+ALT, SPACE, exec, hyprctl switchxkblayout at-translated-set-2-keyboard next"

            # Hypr ecosystem tools
            "C, exec, hyprpicker -a"

            # Consistent key to leave any scratchpad and return to previous workspace
            "Escape, workspace, previous"

            # Screenshot keybindings
            "Print, exec, grimblast --notify copysave area"
            "+SHIFT, Print, exec, grimblast --notify copysave output"
            "+SUPER, Print, exec, grimblast --notify copysave active"
          ];
        bindl = [
          ",switch:Lid Switch, exec, ${toggleDisplayWithLid}"
          ",switch:on:Lid Switch, exec, hyprlock"
          ",switch:off:Lid Switch, exec, hyprctl dispatch dpms on"
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
        # Resize submap - use binde for repeatable resize actions
        submap = resize
        binde = , m, resizeactive, -20 0
        binde = , n, resizeactive, 0 20
        binde = , e, resizeactive, 0 -20
        binde = , i, resizeactive, 20 0
        bind = , escape, submap, reset
        submap = reset

        # Scratchpad submap - auto-exit after any key press
        submap = scratchpad, reset
        bind = , t, togglespecialworkspace, terminal
        bind = SHIFT, t, movetoworkspacesilent, special:terminal
        bind = , s, togglespecialworkspace, scratchpad
        bind = SHIFT, s, movetoworkspacesilent, special:scratchpad
        bind = , escape, submap, reset
        submap = reset

        # Quick actions submap - app launcher/focus and system actions
        submap = quickactions, reset
        # App launcher/focus - tries to focus existing window, otherwise launches
        bind = , s, exec, focus-or-launch signal "signal-desktop --start-in-tray"
        bind = , t, exec, focus-or-launch telegramdesktop telegram-desktop
        bind = , k, exec, focus-or-launch org.keepassxc.KeePassXC keepassxc
        bind = , b, exec, focus-or-launch zen zen
        bind = , o, exec, focus-or-launch obsidian obsidian
        # System actions
        bind = , l, exec, hyprlock
        bind = , p, exec, pavucontrol
        bind = , c, exec, hyprpicker -a
        bind = , d, exec, swaync-client -d
        bind = , w, exec, pkill -SIGUSR1 eww || eww open bar
        bind = , z, exec, pkill -SIGUSR1 eww || eww open bar
        bind = , y, exec, hyprctl switchxkblayout at-translated-set-2-keyboard next
        bind = , h, exec, ${term} -e hyprland-keybindings-help
        bind = , question, exec, ${term} -e hyprland-keybindings-help
        bind = , escape, submap, reset
        submap = reset

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

    # Hyprpaper for wallpaper management
    services.hyprpaper = {
      enable = lib.mkDefault true;
    };

    programs.wallpaperd = with lib; {
      enable = mkDefault false;
      enableHyprlandIntegration = mkDefault false;
    };

    # notifications daemon
    services.mako = {
      enable = lib.mkDefault true;
      settings.anchor = lib.mkDefault "top-center";
      settings.defaultTimeout = lib.mkDefault 2750;
    };

    services.blueman-applet.enable = lib.mkDefault true;
    # Replaced with hyprsunset in exec-once
    services.gammastep = {
      enable = lib.mkDefault false;
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
      wl-clipboard
      wofi
      # Hypr ecosystem tools
      hyprpicker
      hyprsunset
      hyprsysteminfo
      # Productivity and system tools
      grimblast
      swaynotificationcenter
      btop
      eww
      hyprlock
      # Custom scripts
      (writeShellApplication {
        name = "hyprland-keybindings-help";
        runtimeInputs = [];
        text = ''
          #!/usr/bin/env bash
          # Set terminal title for window matching
          echo -ne "\033]0;Hyprland Keybindings\007"
          cat << 'INNEREOF' | less -R
          ┌─────────────────────────────────────────────────────────────────────────────┐
          │                         HYPRLAND KEYBINDINGS                                │
          ├─────────────────────────────────────────────────────────────────────────────┤
          │                                                                             │
          │  MOD = SUPER KEY (Windows/Command)                                         │
          │  Navigation: M=Left N=Down E=Up I=Right (Colemak-DH)                       │
          │                                                                             │
          ├─────────────────────────────────────────────────────────────────────────────┤
          │ WINDOW MANAGEMENT                                                           │
          ├─────────────────────────────────────────────────────────────────────────────┤
          │  MOD+T              Open terminal                                           │
          │  MOD+Q              Close active window                                     │
          │  MOD+Shift+Q        Exit Hyprland                                           │
          │  MOD+F              Toggle fullscreen                                       │
          │  MOD+Shift+F        Toggle floating                                         │
          │  MOD+Shift+P        Pin window (float on all workspaces)                    │
          │  MOD+Space          Application launcher (anyrun)                             │
          │  MOD+Tab            Cycle to next window                                    │
          │                                                                             │
          ├─────────────────────────────────────────────────────────────────────────────┤
          │ WINDOW NAVIGATION (Colemak-DH)                                              │
          ├─────────────────────────────────────────────────────────────────────────────┤
          │  MOD+M              Focus left                                              │
          │  MOD+N              Focus down                                              │
          │  MOD+E              Focus up                                                │
          │  MOD+I              Focus right                                             │
          │  MOD+Shift+M        Swap window left                                        │
          │  MOD+Shift+N        Swap window down                                        │
          │  MOD+Shift+E        Swap window up                                          │
          │  MOD+Shift+I        Swap window right                                       │
          │                                                                             │
          ├─────────────────────────────────────────────────────────────────────────────┤
          │ WORKSPACES                                                                  │
          ├─────────────────────────────────────────────────────────────────────────────┤
          │  MOD+1-9            Switch to workspace 1-9                                 │
          │  MOD+0              Switch to workspace 10                                  │
          │  MOD+Shift+1-9      Move window to workspace 1-9                            │
          │  MOD+Shift+0        Move window to workspace 10                             │
          │  MOD+Alt+M          Previous workspace                                      │
          │  MOD+Alt+I          Next workspace                                          │
          │  MOD+Scroll         Scroll through workspaces                               │
          │                                                                             │
          ├─────────────────────────────────────────────────────────────────────────────┤
          │ SUBMAPS (Modes) - Press MOD + key to enter, ESC to exit                     │
          ├─────────────────────────────────────────────────────────────────────────────┤
          │  MOD+A              Quick Actions menu:                                     │
          │                       S=Signal  T=Telegram  K=KeePassXC                     │
          │                       B=Zen     O=Obsidian  L=Lock                          │
          │                       P=Pavucontrol  C=Color picker  D=Notifications        │
          │                       W/Z=Eww bar    Y=Toggle layout    H/?=Help            │
          │                       (focuses existing window or launches new)             │
          │  MOD+R              Resize mode: M/N/E/I to resize, ESC to exit             │
          │  MOD+S              Scratchpad mode: T=terminal S=scratchpad                │
          │                                                                             │
          ├─────────────────────────────────────────────────────────────────────────────┤
          │ SPECIAL WORKSPACES                                                          │
          ├─────────────────────────────────────────────────────────────────────────────┤
          │  MOD+              Toggle terminal scratchpad                              │
          │  MOD+Shift+        Move window to terminal scratchpad                      │
          │  MOD+Escape         Return to previous workspace                            │
          │                                                                             │
          ├─────────────────────────────────────────────────────────────────────────────┤
          │ SCREENSHOTS                                                                 │
          ├─────────────────────────────────────────────────────────────────────────────┤
          │  Print              Screenshot area (copy + save)                           │
          │  Shift+Print        Screenshot output/monitor (copy + save)                 │
          │  MOD+Print          Screenshot active window (copy + save)                  │
          │                                                                             │
          ├─────────────────────────────────────────────────────────────────────────────┤
          │ MEDIA & BRIGHTNESS                                                          │
          ├─────────────────────────────────────────────────────────────────────────────┤
          │  XF86AudioMute      Toggle mute                                             │
          │  XF86AudioRaiseVol  Volume up                                               │
          │  XF86AudioLowerVol  Volume down                                             │
          │  XF86AudioNext      Next track                                              │
          │  XF86AudioPrev      Previous track                                          │
          │  XF86AudioPlay      Play/Pause                                              │
          │  XF86MonBrightness+ Brightness up                                           │
          │  XF86MonBrightness- Brightness down                                         │
          │                                                                             │
          ├─────────────────────────────────────────────────────────────────────────────┤
          │ OTHER                                                                       │
          ├─────────────────────────────────────────────────────────────────────────────┤
          │  MOD+C              Color picker (hyprpicker)                               │
          │  MOD+MouseDrag      Move/resize windows                                     │
          │                                                                             │
          │  MOD+Shift+Ctrl+Alt+Space   Toggle QWERTY/Colemak-DH layout (mega keychord) │
          │                                                                             │
          └─────────────────────────────────────────────────────────────────────────────┘
          INNEREOF
        '';
      })
      (writeShellApplication {
        name = "focus-or-launch";
        runtimeInputs = [pkgs.jq];
        text = ''
          #!/usr/bin/env bash
          WINDOW_CLASS="$1"
          shift
          if hyprctl clients -j | jq -e ".[] | select(.class | test(\"$WINDOW_CLASS\"; \"i\"))" > /dev/null 2>&1; then
              hyprctl dispatch focuswindow "class:^($WINDOW_CLASS)$"
          else
              "$@" &
          fi
        '';
      })
    ];
  };
}
