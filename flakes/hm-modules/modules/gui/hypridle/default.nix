# Hypridle idle daemon configuration
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.hypridle;
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
              on-timeout = "${pkgs.brightnessctl}/bin/brightnessctl -s set 10";
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
          ];
      };
    };
  };
}
