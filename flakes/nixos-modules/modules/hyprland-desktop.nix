{
  lib,
  config,
  pkgs,
  ...
}: let
  # Eww configuration for the greeter session (simplified bar)
  ewwGreetYuck = pkgs.writeText "greet-eww.yuck" ''
    ; Greeter eww bar - Rose Pine Moon themed
    ; Simplified: time, date, brightness, volume, battery, keyboard layout

    ; Variables
    (defpoll time :interval "1s" "date '+%I:%M %p'")
    (defpoll date :interval "60s" "date '+%a %b %d'")
    (defpoll battery :interval "30s" "cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo 100")
    (defpoll battery-status :interval "30s" "cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo 'Full'")
    (defpoll volume :interval "1s" "pamixer --get-volume 2>/dev/null || echo 0")
    (defpoll volume-muted :interval "1s" "pamixer --get-mute 2>/dev/null || echo false")
    (defpoll brightness :interval "1s" "brightnessctl -m | cut -d',' -f4 | tr -d '%' 2>/dev/null || echo 100")
    (defpoll keyboard-layout :interval "2s" "hyprctl devices -j 2>/dev/null | jq -r '.keyboards[] | select(.main == true) | .active_keymap' | cut -d'(' -f2 | cut -d')' -f1 || echo 'us'")

    ; Widgets
    (defwidget clock []
      (box :class "clock" :orientation "h" :space-evenly false
        (label :text time)))

    (defwidget date-widget []
      (box :class "date" :orientation "h" :space-evenly false
        (label :text date)))

    (defwidget battery-widget []
      (box :class "battery ''${battery-status == 'Charging' ? "charging" : ""}"
           :orientation "h" :space-evenly false
           :tooltip "Battery: ''${battery}% (''${battery-status})"
        (label :text {battery < 20 ? "󰁺" :
                      battery < 40 ? "󰁼" :
                      battery < 60 ? "󰁾" :
                      battery < 80 ? "󰂀" : "󰁹"})
        (label :text "''${battery}%")))

    (defwidget volume-widget []
      (eventbox :onclick "pamixer -t"
        (box :class "volume ''${volume-muted == "true" ? "muted" : ""}"
             :orientation "h" :space-evenly false
             :tooltip "Volume: ''${volume}%"
          (label :text {volume-muted == "true" ? "󰝟" :
                        volume < 30 ? "󰕿" :
                        volume < 70 ? "󰖀" : "󰕾"})
          (label :text "''${volume}%"))))

    (defwidget brightness-widget []
      (box :class "brightness" :orientation "h" :space-evenly false
           :tooltip "Brightness: ''${brightness}%"
        (label :text {brightness < 30 ? "󰃞" :
                      brightness < 70 ? "󰃟" : "󰃠"})
        (label :text "''${brightness}%")))

    (defwidget keyboard-widget []
      (box :class "keyboard"
           :orientation "h" :space-evenly false
           :tooltip "Keyboard layout (Super+Shift+Ctrl+Alt+Space to toggle)"
        (label :text {keyboard-layout == "us" ? "󰌌 US" :
                      keyboard-layout == "basic" ? "󰌌 QW" :
                      keyboard-layout == "colemak_dh" ? "󰌌 CM" : "󰌌 ''${keyboard-layout}"})))

    ; Bar sections
    (defwidget left []
      (box :class "left" :orientation "h" :space-evenly false :halign "start"
        (clock)))

    (defwidget center []
      (box :class "center" :orientation "h" :space-evenly false :halign "center"
        (date-widget)))

    (defwidget right []
      (box :class "right" :orientation "h" :space-evenly false :halign "end"
        (keyboard-widget)
        (brightness-widget)
        (volume-widget)
        (battery-widget)))

    (defwidget bar []
      (centerbox :class "bar"
        (left)
        (center)
        (right)))

    ; Windows
    (defwindow bar
      :monitor 0
      :geometry (geometry :x "0%" :y "4px" :width "99%" :height "32px" :anchor "top center")
      :stacking "fg"
      :exclusive false
      :focusable false
      (bar))
  '';

  ewwGreetScss = pkgs.writeText "greet-eww.scss" ''
    // Rose Pine Moon theme for Greeter Eww
    $base: #232136;
    $surface: #2a273f;
    $overlay: #393552;
    $muted: #6e6a86;
    $subtle: #908caa;
    $text: #e0def4;
    $love: #eb6f92;
    $gold: #f6c177;
    $rose: #ea9a97;
    $pine: #3e8fb0;
    $foam: #9ccfd8;
    $iris: #c4a7e7;
    $highlight-low: #2a283e;
    $highlight-med: #44415a;
    $highlight-high: #56526e;

    * {
      all: unset;
      font-family: "Inter", "JetBrainsMono Nerd Font", sans-serif;
      font-size: 14px;
    }

    .bar {
      background: transparent;
    }

    .left, .center, .right {
      background: $base;
      border-radius: 8px;
      padding: 6px 12px;
      margin: 4px;
    }

    .clock {
      color: $iris;
      font-weight: bold;
      padding: 0 8px;
    }

    .date {
      color: $subtle;
      padding: 0 8px;
    }

    .battery {
      color: $foam;
      padding: 0 8px;

      &.charging {
        color: $gold;
      }

      label:first-child {
        margin-right: 4px;
      }
    }

    .volume {
      color: $iris;
      padding: 0 8px;

      &.muted {
        color: $muted;
      }

      label:first-child {
        margin-right: 4px;
      }
    }

    .brightness {
      color: $gold;
      padding: 0 8px;

      label:first-child {
        margin-right: 4px;
      }
    }

    .keyboard {
      color: $rose;
      padding: 0 8px;
      font-weight: bold;
      background: $overlay;
      border-radius: 4px;
      margin-right: 8px;
    }
  '';

  # Eww config directory for greeter
  ewwGreetConfigDir = pkgs.runCommand "greetd-eww-config" {} ''
    mkdir -p $out
    cp ${ewwGreetYuck} $out/eww.yuck
    cp ${ewwGreetScss} $out/eww.scss
  '';

  greetdFixDockedLidDisplays = pkgs.writeShellApplication {
    name = "greetd-fix-docked-lid-displays";
    runtimeInputs = [pkgs.coreutils pkgs.gnugrep pkgs.hyprland pkgs.jq];
    text = ''
      # Hyprland starts before any user-level kanshi service is available. When
      # a laptop boots docked with the lid closed, the internal panel can remain
      # the primary greeter output even though nobody can see it. If the lid is
      # closed and at least one external monitor is present, disable eDP-* for
      # the greetd session so ReGreet is forced onto the visible display.
      for _ in $(seq 1 20); do
        monitors_json="$(hyprctl monitors -j 2>/dev/null || true)"
        if [ -n "$monitors_json" ] && printf '%s' "$monitors_json" | jq -e 'type == "array"' >/dev/null; then
          break
        fi
        sleep 0.1
      done

      lid_closed=false
      for lid_state in /proc/acpi/button/lid/*/state; do
        if [ -r "$lid_state" ] && grep -qi 'closed' "$lid_state"; then
          lid_closed=true
          break
        fi
      done

      if [ "$lid_closed" != true ]; then
        exit 0
      fi

      external_count="$(printf '%s' "$monitors_json" | jq '[.[] | select(.name | test("^eDP-") | not)] | length')"
      if [ "''${external_count:-0}" -eq 0 ]; then
        exit 0
      fi

      printf '%s' "$monitors_json" \
        | jq -r '.[] | select(.name | test("^eDP-")) | .name' \
        | while IFS= read -r monitor; do
          hyprctl keyword monitor "$monitor,disable" >/dev/null || true
        done
    '';
  };

  # Hyprland configuration for the ReGreet session
  hyprlandGreetConfig = pkgs.writeText "greetd-hyprland-config" ''
    # ReGreet session - Fun and colorful theme
    env = GDK_BACKEND,wayland
    env = XCURSOR_SIZE,24
    env = HYPRCURSOR_SIZE,24

    # Run eww bar and ReGreet
    exec-once = ${lib.getExe greetdFixDockedLidDisplays}
    exec-once = eww -c ${ewwGreetConfigDir} open bar
    exec-once = ${lib.getExe pkgs.regreet}; hyprctl dispatch exit

    # Window rule to make ReGreet fullscreen and centered
    windowrule = fullscreen, ^(regreet)$
    windowrule = center, ^(regreet)$
    windowrule = noblur, ^(regreet)$
    windowrule = noanim, ^(regreet)$

    # Essential keybindings for power/reboot
    bind = SUPER+SHIFT, Q, exec, systemctl poweroff
    bind = SUPER+SHIFT, R, exec, systemctl reboot

    # Keyboard layout toggle: Colemak-DH <-> QWERTY
    # Uses the same mega keychord as your main Hyprland config
    bind = SUPER+SHIFT+CTRL+ALT, SPACE, exec, hyprctl switchxkblayout at-translated-set-2-keyboard next

    # Basic input settings
    input {
      kb_layout = us, us
      kb_variant = colemak_dh, basic
      kb_options = grp:alt_shift_toggle
      numlock_by_default = true
      follow_mouse = 1
      touchpad {
        clickfinger_behavior = true
      }
    }

    # Device-specific keyboard configuration
    device {
      name = at-translated-set-2-keyboard
      kb_layout = us, us
      kb_variant = colemak_dh, basic
      resolve_binds_by_sym = 1
    }

    # Visual settings - minimal since ReGreet is fullscreen
    general {
      gaps_in = 0
      gaps_out = 0
      border_size = 0
      layout = dwindle
    }

    decoration {
      rounding = 0
      blur {
        enabled = false
      }
      shadow {
        enabled = false
      }
    }

    animations {
      enabled = false
    }

    misc {
      disable_hyprland_logo = true
      disable_splash_rendering = true
    }
  '';
in {
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

    # ReGreet - Modern, customizable greeter with fun theme
    programs.regreet = {
      enable = true;
      settings = {
        GTK = {
          application_prefer_dark_theme = true;
        };
        commands = {
          reboot = ["systemctl" "reboot"];
          poweroff = ["systemctl" "poweroff"];
        };
      };
      extraCss = ''
        /* Fun and Appealing ReGreet Theme */
        /* Inspired by Catppuccin Mocha with custom flair */

        @define-color bg #1e1e2e;
        @define-color bg-dark #11111b;
        @define-color bg-light #313244;
        @define-color fg #cdd6f4;
        @define-color fg-dim #a6adc8;
        @define-color accent #cba6f7;
        @define-color accent2 #89dceb;
        @define-color error #f38ba8;
        @define-color success #a6e3a1;
        @define-color warning #f9e2af;

        * {
          font-family: "JetBrainsMono Nerd Font", "Inter", sans-serif;
          font-size: 14px;
        }

        window {
          background: linear-gradient(135deg,
            alpha(@bg-dark, 0.95) 0%,
            alpha(@bg, 0.98) 50%,
            alpha(#302d41, 0.95) 100%);
        }

        /* Main container styling */
        .container {
          background: alpha(@bg, 0.85);
          border-radius: 24px;
          padding: 40px;
          box-shadow:
            0 0 0 1px alpha(@accent, 0.3),
            0 20px 60px alpha(@bg-dark, 0.8),
            0 0 100px alpha(@accent, 0.1);
          border: 1px solid alpha(@accent, 0.2);
        }

        /* Welcome label */
        label.welcome {
          font-size: 32px;
          font-weight: bold;
          color: @accent;
          margin-bottom: 24px;
          text-shadow: 0 0 20px alpha(@accent, 0.5);
        }

        /* Clock styling */
        label.clock {
          font-size: 72px;
          font-weight: 200;
          color: @fg;
          margin-bottom: 8px;
          letter-spacing: 2px;
        }

        label.date {
          font-size: 16px;
          color: @fg-dim;
          margin-bottom: 40px;
          text-transform: uppercase;
          letter-spacing: 3px;
        }

        /* User selection */
        .user-list {
          margin: 20px 0;
        }

        button.user {
          background: alpha(@bg-light, 0.6);
          border: 2px solid transparent;
          border-radius: 16px;
          padding: 16px 32px;
          margin: 8px;
          transition: all 200ms ease;
        }

        button.user:hover {
          background: alpha(@accent, 0.15);
          border-color: alpha(@accent, 0.5);
          box-shadow: 0 0 20px alpha(@accent, 0.2);
        }

        button.user:focus {
          background: alpha(@accent, 0.2);
          border-color: @accent;
          box-shadow: 0 0 30px alpha(@accent, 0.4);
        }

        button.user label {
          color: @fg;
          font-size: 18px;
          font-weight: 600;
        }

        /* Password entry */
        entry {
          background: alpha(@bg-light, 0.5);
          border: 2px solid alpha(@accent, 0.3);
          border-radius: 12px;
          padding: 12px 20px;
          color: @fg;
          font-size: 16px;
          min-width: 300px;
          transition: all 200ms ease;
        }

        entry:focus {
          background: alpha(@bg-light, 0.8);
          border-color: @accent;
          box-shadow: 0 0 15px alpha(@accent, 0.3);
        }

        entry:placeholder {
          color: @fg-dim;
        }

        /* Login button */
        button.login {
          background: linear-gradient(135deg, @accent, @accent2);
          border: none;
          border-radius: 12px;
          padding: 14px 40px;
          margin-top: 20px;
          color: @bg-dark;
          font-size: 16px;
          font-weight: bold;
          transition: all 200ms ease;
        }

        button.login:hover {
          background: @accent2;
          box-shadow: 0 5px 25px alpha(@accent, 0.4);
        }

        /* Power buttons */
        button.power {
          background: alpha(@bg-light, 0.4);
          border: 1px solid alpha(@fg-dim, 0.2);
          border-radius: 50%;
          min-width: 48px;
          min-height: 48px;
          padding: 12px;
          margin: 8px;
          transition: all 200ms ease;
        }

        button.power:hover {
          background: alpha(@error, 0.2);
          border-color: alpha(@error, 0.5);
        }

        button.power.reboot:hover {
          background: alpha(@warning, 0.2);
          border-color: alpha(@warning, 0.5);
        }

        button.power label {
          color: @fg-dim;
          font-size: 20px;
        }

        button.power:hover label {
          color: @fg;
        }

        /* Error message */
        label.error {
          color: @error;
          font-size: 14px;
          margin-top: 12px;
          padding: 8px 16px;
          background: alpha(@error, 0.1);
          border-radius: 8px;
        }

        /* Session selector */
        .session-selector {
          margin-top: 16px;
        }

        button.session {
          background: transparent;
          border: 1px solid alpha(@fg-dim, 0.2);
          border-radius: 8px;
          padding: 8px 16px;
          color: @fg-dim;
          font-size: 13px;
        }

        button.session:hover {
          background: alpha(@bg-light, 0.5);
          border-color: alpha(@accent, 0.4);
          color: @fg;
        }

        /* Keyboard layout indicator */
        label.keyboard {
          font-size: 12px;
          color: @fg-dim;
          background: alpha(@bg-light, 0.5);
          padding: 6px 12px;
          border-radius: 6px;
          margin-top: 12px;
        }

        /* Soft gradient overlay */
        .overlay-gradient {
          background: alpha(@accent, 0.03);
        }
      '';
    };

    # Greetd configuration - runs ReGreet in a Hyprland session
    services.greetd = {
      enable = true;
      settings.default_session = {
        command = "${pkgs.dbus}/bin/dbus-run-session ${lib.getExe pkgs.hyprland} --config ${hyprlandGreetConfig}";
        user = "greeter";
      };
    };

    # ReGreet reads this list to decide what command to launch after a
    # successful login. Without it, password auth succeeds but the selected
    # session can immediately exit and bounce back to the greeter.
    environment.etc."greetd/environments".text = ''
      Hyprland
      zsh
      bash
    '';

    # Ensure systemd logs don't overlap with greetd
    boot.kernelParams = [
      "console=tty1"
    ];

    # System packages needed for Hyprland desktop
    environment.systemPackages = with pkgs; [
      wl-clipboard
      wdisplays # Monitor configuration GUI
      brightnessctl
      playerctl
      pamixer
      libnotify
      eww # Widget system for the greeter bar
      jq # Needed for keyboard layout detection in eww
    ];
  };
}
