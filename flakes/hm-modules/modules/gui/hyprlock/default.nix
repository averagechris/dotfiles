# Hyprlock screen locker with Rose Pine Moon theme
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.hyprlock;
in {
  options.dotfiles.hyprlock = {
    enable = lib.mkEnableOption "Hyprlock screen locker";
  };

  config = lib.mkIf cfg.enable {
    programs.hyprlock = {
      enable = true;

      settings = {
        general = {
          disable_loading_bar = false;
          hide_cursor = true;
          grace = 5;
          no_fade_in = false;
        };

        background = [
          {
            path = "screenshot";
            blur_passes = 3;
            blur_size = 8;
            noise = 0.0117;
            contrast = 0.8916;
            brightness = 0.8172;
            vibrancy = 0.1696;
            vibrancy_darkness = 0.0;
          }
        ];

        input-field = [
          {
            size = "250, 50";
            outline_thickness = 2;
            dots_size = 0.2;
            dots_spacing = 0.35;
            dots_center = true;
            outer_color = "rgba(147, 153, 178, 0.25)"; # subtle with transparency
            inner_color = "rgba(35, 33, 54, 0.9)"; # base with transparency
            font_color = "rgb(224, 222, 244)"; # text
            fade_on_empty = false;
            placeholder_text = "<i>Password...</i>";
            hide_input = false;
            position = "0, -120";
            halign = "center";
            valign = "center";
          }
        ];

        label = [
          {
            # Time
            text = "cmd[update:1000] date +%H:%M";
            color = "rgb(224, 222, 244)"; # text
            font_size = 90;
            font_family = "Inter Bold";
            position = "0, 80";
            halign = "center";
            valign = "center";
          }
          {
            # Date
            text = "cmd[update:1000] date '+%A, %B %d'";
            color = "rgb(144, 140, 170)"; # subtle
            font_size = 20;
            font_family = "Inter";
            position = "0, -20";
            halign = "center";
            valign = "center";
          }
          {
            # Now playing (optional)
            text = "cmd[update:1000] playerctl metadata --format '{{artist}} - {{title}}' 2>/dev/null || echo ''";
            color = "rgb(144, 140, 170)"; # subtle
            font_size = 14;
            font_family = "Inter";
            position = "0, -200";
            halign = "center";
            valign = "center";
          }
        ];
      };
    };
  };
}
