# Hypridle idle daemon configuration
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.hypridle;
  dimScreen = pkgs.writeShellApplication {
    name = "hypridle-dim-screen";
    runtimeInputs = [pkgs.brightnessctl pkgs.coreutils];
    text = ''
      current=$(brightnessctl g)
      max=$(brightnessctl m)

      if [ -z "$current" ] || [ -z "$max" ] || [ "$max" -le 0 ]; then
        exit 0
      fi

      # Dim relative to current brightness (about 30%), never increase
      target=$((current / 3))
      if [ "$target" -lt 1 ]; then
        target=1
      fi

      brightnessctl -s set "$target"
    '';
  };
  idleInhibit = pkgs.writeShellApplication {
    name = "dotfiles-idle-inhibit";
    runtimeInputs = [pkgs.coreutils pkgs.gawk pkgs.hyprland pkgs.jq];
    text = ''
      set -euo pipefail

      state_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/dotfiles-idle-inhibit"
      state_file="$state_dir/state"

      power_state() {
        local found=0 online=0 supply
        shopt -s nullglob
        for supply in /sys/class/power_supply/*; do
          if [[ -r "$supply/type" && -r "$supply/online" ]] && [[ "$(<"$supply/type")" == "Mains" ]]; then
            found=1
            if [[ "$(<"$supply/online")" == "1" ]]; then
              online=1
            fi
          fi
        done
        shopt -u nullglob

        if [[ "$found" -eq 0 ]]; then
          printf 'mains:unknown'
        elif [[ "$online" -eq 1 ]]; then
          printf 'mains:online'
        else
          printf 'mains:offline'
        fi
      }

      lid_state() {
        local lid
        shopt -s nullglob
        for lid in /proc/acpi/button/lid/*/state; do
          awk '{print "lid:" $2}' "$lid"
          shopt -u nullglob
          return 0
        done
        shopt -u nullglob
        printf 'lid:unknown\n'
      }

      monitor_state() {
        hyprctl monitors -j 2>/dev/null \
          | jq -c '[.[] | {name, model, disabled}] | sort_by(.name)' \
          || printf 'monitors:unknown\n'
      }

      signature() {
        {
          power_state
          printf '\n'
          lid_state
          monitor_state
        } | sha256sum | cut -d' ' -f1
      }

      active() {
        if [[ ! -f "$state_file" ]]; then
          return 1
        fi

        if [[ "$(<"$state_file")" == "$(signature)" ]]; then
          return 0
        fi

        rm -f "$state_file"
        return 1
      }

      case "''${1:-status}" in
        active)
          active
          ;;
        status)
          if active; then printf 'active\n'; else printf 'inactive\n'; fi
          ;;
        eww-label)
          if active; then printf '󰅶'; else printf '󰾪'; fi
          ;;
        toggle)
          if active; then
            rm -f "$state_file"
          else
            mkdir -p "$state_dir"
            signature >"$state_file"
          fi
          ;;
        off|clear)
          rm -f "$state_file"
          ;;
        *)
          printf 'usage: dotfiles-idle-inhibit [active|status|eww-label|toggle|off|clear]\n' >&2
          exit 2
          ;;
      esac
    '';
  };
in {
  options.dotfiles.hypridle = {
    enable = lib.mkEnableOption "Hypridle idle daemon";

    timeouts = {
      dim = lib.mkOption {
        type = lib.types.int;
        default = 150;
        description = "Seconds before dimming screen";
      };
      lock = lib.mkOption {
        type = lib.types.int;
        default = 300;
        description = "Seconds before locking screen";
      };
      dpms = lib.mkOption {
        type = lib.types.int;
        default = 330;
        description = "Seconds before turning off display";
      };
      suspend = lib.mkOption {
        type = lib.types.int;
        default = 900;
        description = "Seconds before suspending (0 to disable)";
      };
      hibernate = lib.mkOption {
        type = lib.types.int;
        default = 0;
        description = "Seconds before hibernating (0 to disable)";
      };
    };

    idleInhibit.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install dotfiles-idle-inhibit and make default Hypridle listeners honor it.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = lib.mkIf cfg.idleInhibit.enable [idleInhibit];

    services.hypridle = {
      enable = true;

      settings = {
        general = {
          lock_cmd = "pidof hyprlock || hyprlock";
          before_sleep_cmd = "loginctl lock-session";
          after_sleep_cmd = "hyprctl dispatch dpms on";
        };

        listener = let
          inhibited = command:
            if cfg.idleInhibit.enable
            then "if ! ${lib.getExe idleInhibit} active; then ${command}; fi"
            else command;
        in
          [
            {
              # Dim screen
              timeout = cfg.timeouts.dim;
              on-timeout = inhibited "${dimScreen}/bin/hypridle-dim-screen";
              on-resume = "${pkgs.brightnessctl}/bin/brightnessctl -r";
            }
            {
              # Lock screen
              timeout = cfg.timeouts.lock;
              on-timeout = inhibited "loginctl lock-session";
            }
            {
              # Turn off display
              timeout = cfg.timeouts.dpms;
              on-timeout = inhibited "hyprctl dispatch dpms off";
              on-resume = "hyprctl dispatch dpms on";
            }
          ]
          ++ lib.optionals (cfg.timeouts.suspend > 0) [
            {
              # Suspend
              timeout = cfg.timeouts.suspend;
              on-timeout = inhibited "systemctl suspend";
            }
          ]
          ++ lib.optionals (cfg.timeouts.hibernate > 0) [
            {
              # Hibernate
              timeout = cfg.timeouts.hibernate;
              on-timeout = inhibited "systemctl hibernate";
            }
          ];
      };
    };
  };
}
