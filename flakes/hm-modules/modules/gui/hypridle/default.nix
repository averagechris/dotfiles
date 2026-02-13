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
  };

  config = lib.mkIf cfg.enable {
    services.hypridle = {
      enable = true;

      settings = {
        general = {
          lock_cmd = "pidof hyprlock || hyprlock";
          before_sleep_cmd = "loginctl lock-session";
          after_sleep_cmd = "hyprctl dispatch dpms on";
        };

        listener =
          [
            {
              # Dim screen
              timeout = cfg.timeouts.dim;
              on-timeout = "${dimScreen}/bin/hypridle-dim-screen";
              on-resume = "${pkgs.brightnessctl}/bin/brightnessctl -r";
            }
            {
              # Lock screen
              timeout = cfg.timeouts.lock;
              on-timeout = "loginctl lock-session";
            }
            {
              # Turn off display
              timeout = cfg.timeouts.dpms;
              on-timeout = "hyprctl dispatch dpms off";
              on-resume = "hyprctl dispatch dpms on";
            }
          ]
          ++ lib.optionals (cfg.timeouts.suspend > 0) [
            {
              # Suspend
              timeout = cfg.timeouts.suspend;
              on-timeout = "systemctl suspend";
            }
          ]
          ++ lib.optionals (cfg.timeouts.hibernate > 0) [
            {
              # Hibernate
              timeout = cfg.timeouts.hibernate;
              on-timeout = "systemctl hibernate";
            }
          ];
      };
    };
  };
}
