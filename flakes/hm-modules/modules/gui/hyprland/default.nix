{
  config,
  dotfiles_lib,
  pkgs,
  lib,
  ...
}: let
  cfg = config.dotfiles.gui.hyprland;
  hctlCfg = cfg.hctl;
  term = config.dotfiles.gui.terminal.binPath;
  hctlPackage = pkgs.rustPlatform.buildRustPackage {
    pname = "hctl";
    version = "0.1.0";
    src = ./hctl;
    cargoLock = {
      lockFile = ./hctl/Cargo.lock;
      outputHashes = {};
    };
    nativeBuildInputs = [pkgs.makeWrapper];
    postFixup = ''
      wrapProgram $out/bin/hctl \
        --prefix PATH : ${lib.makeBinPath ([pkgs.hyprland pkgs.keepassxc pkgs.signal-desktop] ++ lib.optionals (pkgs ? telegram-desktop) [pkgs.telegram-desktop])}
    '';
    meta = {
      description = "Hyprland ergonomics control CLI and daemon";
      license = lib.licenses.mit;
    };
  };
  hctlConfig = {
    inherit (hctlCfg) apps workspaces;
    smartGaps = {
      enabled = hctlCfg.smartGaps.enable;
      inherit (hctlCfg.smartGaps) profiles resetGaps;
    };
    eww.stateFile = hctlCfg.eww.stateFile;
  };
  toggleDisplayWithLid = let
    name = "disable-builtin-display-when-lid-closed";
    script = pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [pkgs.coreutils pkgs.hyprland pkgs.jq config.programs.eww.package];
      text = ''
        refresh_bars() {
          external_bar_for_monitor() {
            case "$1" in
              DP-1) printf '%s\n' bar-external-dp1 ;;
              DP-2) printf '%s\n' bar-external ;;
              DP-3) printf '%s\n' bar-external-dp3 ;;
              HDMI-A-1) printf '%s\n' bar-external-hdmi-a-1 ;;
              HDMI-A-2) printf '%s\n' bar-external-hdmi-a-2 ;;
              *) return 1 ;;
            esac
          }

          close_external_bars() {
            local keep="''${1:-}"
            for bar in bar-external-dp1 bar-external bar-external-dp3 bar-external-hdmi-a-1 bar-external-hdmi-a-2; do
              [[ "$bar" == "$keep" ]] && continue
              eww close "$bar" || true
            done
          }

          # Keep exactly one bar open, matching eww-open-bars' startup policy.
          external_monitor="$(hyprctl monitors -j | jq -r 'first(.[] | select(.name != "eDP-1" and (((.disabled // false) | not))) | .name) // empty')"
          if [[ -n "$external_monitor" ]] && external_bar="$(external_bar_for_monitor "$external_monitor")"; then
            eww open "$external_bar" || true
            eww close bar-internal || true
            close_external_bars "$external_bar"
          elif hyprctl monitors -j | jq -e '.[] | select(.name == "eDP-1" and (((.disabled // false) | not)))' >/dev/null; then
            eww open bar-internal || true
            close_external_bars
          else
            eww close bar-internal || true
            close_external_bars
          fi
        }

        external_count="$(${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq '[.[] | select(.name != "eDP-1" and (((.disabled // false) | not)))] | length')"

        if grep -q open /proc/acpi/button/lid/LID0/state; then
            hyprctl keyword monitor "eDP-1,preferred,auto,1"
            refresh_bars
        else
            if [[ "$external_count" -gt 0 ]]; then
                hyprctl keyword monitor "eDP-1,disable"
                refresh_bars
            fi
        fi
      '';
    };
  in "${script}/bin/${name}";
  lockOnUndockedLidClose = let
    name = "lock-on-undocked-lid-close";
    script = pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [pkgs.coreutils pkgs.hyprland pkgs.jq];
      text = ''
        external_count="$(hyprctl monitors -j | jq '[.[] | select(.name != "eDP-1")] | length')"

        if [[ "$external_count" -eq 0 ]]; then
          hyprlock
        fi
      '';
    };
  in "${script}/bin/${name}";
in {
  options.dotfiles.gui.hyprland = {
    enable = lib.mkEnableOption "Enable configured hyprland.";
    waybar.enable = dotfiles_lib.options.mkDefaultEnabledOption "Enable waybar with hyprland config";
    overview = {
      enable = lib.mkEnableOption "Hyprspace visual workspace overview";
      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        description = "Hyprspace plugin package built against the active Hyprland package.";
      };
    };
    hctl = {
      enable = dotfiles_lib.options.mkDefaultEnabledOption "hctl Hyprland ergonomics CLI and daemon";
      package = lib.mkOption {
        type = lib.types.package;
        default = hctlPackage;
        description = "hctl package to install and use for Hyprland ergonomics.";
      };
      apps = lib.mkOption {
        type = lib.types.attrs;
        default = {
          keepassxc = {
            match = {
              class = "org.keepassxc.KeePassXC";
              title = null;
              initialClass = null;
              initialTitle = null;
            };
            launch = ["keepassxc"];
            homeWorkspace = null;
            summon = {
              enabled = true;
              floating = true;
              center = true;
              size = {
                width = 900;
                height = 650;
              };
            };
            hide = {
              enabled = true;
              method = "close-to-tray";
            };
            borrow.enabled = false;
          };
          signal = {
            match = {
              class = "signal";
              title = null;
              initialClass = null;
              initialTitle = null;
            };
            launch = ["signal-desktop"];
            homeWorkspace = "chat";
            borrow = {
              enabled = true;
              floating = true;
              center = true;
              size = {
                width = 900;
                height = 1000;
              };
            };
          };
          telegram = {
            match = {
              class = "org.telegram.desktop";
              title = null;
              initialClass = null;
              initialTitle = null;
            };
            launch = ["Telegram"];
            homeWorkspace = "chat";
            borrow = {
              enabled = true;
              floating = true;
              center = true;
              size = {
                width = 900;
                height = 1000;
              };
            };
          };
        };
        description = "Application behavior emitted to hctl's JSON config.";
      };
      workspaces = lib.mkOption {
        type = lib.types.attrs;
        default.chat = {
          name = "chat";
          kind = "named";
        };
        description = "Workspace definitions emitted to hctl's JSON config.";
      };
      smartGaps = {
        enable = lib.mkEnableOption "hctl smart gaps daemon behavior" // {default = true;};
        profiles = lib.mkOption {
          type = lib.types.listOf lib.types.attrs;
          default = [
            {
              name = "taterLaptopPanel";
              match.name = "eDP-1";
              gaps = {
                oneWindow = {
                  inner = 12;
                  outer = 32;
                };
                twoWindows = {
                  inner = 10;
                  outer = 24;
                };
                threeWindows = {
                  inner = 8;
                  outer = 12;
                };
                manyWindows = {
                  inner = 8;
                  outer = 12;
                };
              };
            }
            {
              name = "taterDellDock";
              match.name = "DP-2";
              gaps = {
                oneWindow = {
                  inner = 28;
                  outer = 180;
                };
                twoWindows = {
                  inner = 22;
                  outer = 120;
                };
                threeWindows = {
                  inner = 16;
                  outer = 72;
                };
                manyWindows = {
                  inner = 8;
                  outer = 24;
                };
              };
            }
            {
              name = "laptop";
              match.maxWidth = 1999;
              gaps = {
                oneWindow = {
                  inner = 12;
                  outer = 32;
                };
                twoWindows = {
                  inner = 10;
                  outer = 24;
                };
                threeWindows = {
                  inner = 8;
                  outer = 12;
                };
                manyWindows = {
                  inner = 8;
                  outer = 12;
                };
              };
            }
            {
              name = "externalLarge";
              match.minWidth = 2000;
              gaps = {
                oneWindow = {
                  inner = 28;
                  outer = 180;
                };
                twoWindows = {
                  inner = 22;
                  outer = 120;
                };
                threeWindows = {
                  inner = 16;
                  outer = 72;
                };
                manyWindows = {
                  inner = 8;
                  outer = 24;
                };
              };
            }
          ];
          description = "Monitor-name and width-matched smart gap profiles emitted to hctl's JSON config.";
        };
        resetGaps = lib.mkOption {
          type = lib.types.attrs;
          default = {
            inner = 4;
            outer = 6;
          };
          description = "Base Hyprland gaps restored when smart gaps are disabled for a workspace.";
        };
      };
      eww.stateFile = lib.mkOption {
        type = lib.types.str;
        default = "$XDG_STATE_HOME/hctl/eww-state.json";
        description = "Path where hctl daemon writes Eww-facing JSON state.";
      };
    };
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
      plugins = lib.optionals (cfg.overview.enable && cfg.overview.package != null) [cfg.overview.package];
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
          "eDP-1,preferred,auto,1"
          ",preferred,auto,1"
        ];
        workspace = [
          # Keep workspaces monitor-local when docked. If a monitor is absent,
          # Hyprland still makes the workspace available on the remaining output.
          "1, monitor:DP-2, default:true"
          "2, monitor:DP-2"
          "3, monitor:DP-2"
          "4, monitor:DP-2"
          "5, monitor:DP-2"
          "6, monitor:eDP-1, default:true"
          "7, monitor:eDP-1"
          "8, monitor:eDP-1"
          "9, monitor:eDP-1"
          "10, monitor:eDP-1"
          "name:chat, monitor:DP-2"
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
        "plugin:overview" = lib.mkIf cfg.overview.enable {
          panelHeight = 220;
          panelColor = "rgba(191724dd)";
          panelBorderColor = "rgba(c4a7e7ee)";
          panelBorderWidth = 2;
          onBottom = true;
          workspaceMargin = 12;
          workspaceActiveBackground = "rgba(26233add)";
          workspaceInactiveBackground = "rgba(1f1d2edd)";
          workspaceActiveBorder = "rgba(9ccfd8ff)";
          workspaceInactiveBorder = "rgba(6e6a86aa)";
          workspaceBorderSize = 2;
          centerAligned = true;
          dragAlpha = 0.85;
          autoDrag = true;
          autoScroll = true;
          exitOnClick = true;
          switchOnDrop = true;
          exitOnSwitch = true;
          showEmptyWorkspace = true;
          showNewWorkspace = false;
          showSpecialWorkspace = false;
          exitKey = "Escape";
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
            "+SHIFT, P, exec, hctl toggle-pin"
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
            (
              if cfg.overview.enable
              then "O, overview:toggle, all"
              else "O, exec, hyprland-workspace-overview"
            )

            # Scroll through existing workspaces with mainMod + scroll
            "mouse_right, workspace, e+1"
            "mouse_left, workspace, e-1"

            # Terminal scratchpad (grave/backtick key)
            "grave, togglespecialworkspace, terminal"
            "+SHIFT, grave, movetoworkspacesilent, special:terminal"

            # Scratchpad submap launcher
            "s, submap, scratchpad"

            # Chat/communication actions submap launcher
            "c, submap, chat"

            # Window actions submap launcher
            "w, submap, windowactions"

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
          ",switch:on:Lid Switch, exec, ${lockOnUndockedLidClose}"
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
        bind = , k, exec, hctl summon keepassxc
        bind = SHIFT, k, exec, hctl hide keepassxc
        bind = , p, exec, hctl summon keepassxc
        bind = SHIFT, p, exec, hctl hide keepassxc
        bind = , escape, submap, reset
        submap = reset

        # Chat submap - persistent chat workspace plus borrowed app popups
        submap = chat, reset
        bind = , c, exec, hctl goto chat
        bind = , s, exec, hctl toggle-borrow signal
        bind = , t, exec, hctl toggle-borrow telegram
        bind = , escape, submap, reset
        submap = reset

        # Window actions submap - focused-window hctl helpers
        submap = windowactions, reset
        bind = , v, exec, hctl video-pin
        bind = , z, exec, hctl zen-window
        bind = , p, exec, hctl toggle-pin
        bind = , g, exec, hctl toggle-smart-gaps
        bind = , escape, submap, reset
        submap = reset

        # Quick actions submap - app launcher/focus and system actions
        submap = quickactions, reset
        # App launcher/focus - tries to focus existing window, otherwise launches
        bind = , s, exec, hctl toggle-borrow signal
        bind = , t, exec, hctl toggle-borrow telegram
        bind = , k, exec, hctl summon keepassxc
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

    xdg.configFile."hctl/config.json" = lib.mkIf hctlCfg.enable {
      text = builtins.toJSON hctlConfig;
    };

    systemd.user.services.hctl = lib.mkIf hctlCfg.enable {
      Unit = {
        Description = "hctl Hyprland ergonomics daemon";
        After = ["graphical-session.target"];
        PartOf = ["graphical-session.target"];
      };
      Service = {
        ExecStart = "${hctlCfg.package}/bin/hctl daemon";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = ["graphical-session.target"];
    };

    home.packages =
      lib.optionals hctlCfg.enable [hctlCfg.package]
      ++ (with pkgs; [
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
            │  MOD+Shift+P        Toggle pin for focused window via hctl                   │
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
            │  MOD+O              Toggle visual workspace overview                         │
            │  MOD+Scroll         Scroll through workspaces                               │
            │                                                                             │
            ├─────────────────────────────────────────────────────────────────────────────┤
            │ SUBMAPS (Modes) - Press MOD + key to enter, ESC to exit                     │
            ├─────────────────────────────────────────────────────────────────────────────┤
            │  MOD+A              Quick Actions menu:                                     │
            │                       S=Borrow Signal  T=Borrow Telegram  K=KeePassXC        │
            │                       B=Zen     O=Obsidian  L=Lock                          │
            │                       P=Pavucontrol  C=Color picker  D=Notifications        │
            │                       W/Z=Eww bar    Y=Toggle layout    H/?=Help            │
            │                       (focuses existing window or launches new)             │
            │  MOD+C              Chat mode: C=chat workspace S=Signal T=Telegram          │
            │  MOD+R              Resize mode: M/N/E/I to resize, ESC to exit             │
            │  MOD+S              Scratchpad mode: T=terminal S=scratchpad K/P=KeePassXC  │
            │  MOD+W              Window mode: V=video Z=zen P=pin G=smart gaps            │
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
          name = "hyprland-workspace-overview";
          runtimeInputs = [pkgs.coreutils pkgs.hyprland pkgs.jq pkgs.wofi];
          text = ''
            #!/usr/bin/env bash
            set -euo pipefail

            workspaces_json="$(hyprctl workspaces -j)"
            clients_json="$(hyprctl clients -j)"
            active_json="$(hyprctl activeworkspace -j)"
            active_id="$(jq -r '.id' <<< "$active_json")"

            choices="$({
              for ws in {1..10}; do
                jq -rn \
                  --argjson workspaces "$workspaces_json" \
                  --argjson clients "$clients_json" \
                  --argjson ws "$ws" \
                  --argjson active "$active_id" '
                    def workspace: $workspaces[]? | select(.id == $ws);
                    def client_count: [$clients[]? | select(.workspace.id == $ws)] | length;
                    def titles: [$clients[]? | select(.workspace.id == $ws) | (.title // .class // "window")][0:3] | join(" • ");
                    "go \($ws)\t" +
                    (if $ws == $active then "●" else "○" end) +
                    " workspace \($ws)" +
                    (workspace.monitor as $monitor | if $monitor then " · " + $monitor else "" end) +
                    " · " + (client_count | tostring) + " windows" +
                    (titles as $titles | if $titles == "" then "" else " · " + $titles end),
                    "move \($ws)\t󰁌 move active window → workspace \($ws)"
                  '
              done
            })"

            selection="$(printf '%s\n' "$choices" | wofi --dmenu --prompt "Workspace overview" --width 760 --height 520 --insensitive || true)"
            [[ -n "$selection" ]] || exit 0

            action="''${selection%%$'\t'*}"
            verb="''${action%% *}"
            ws="''${action#* }"

            case "$verb" in
              go)
                hyprctl dispatch workspace "$ws"
                ;;
              move)
                hyprctl dispatch movetoworkspace "$ws"
                hyprctl dispatch workspace "$ws"
                ;;
            esac
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
      ]);
  };
}
