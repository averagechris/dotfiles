{
  config,
  lib,
  ...
}: let
  cfg = config.dotfiles.gui.hyprland.waybar;
in {
  config = lib.mkIf cfg.enable {
    programs.waybar = {
      enable = lib.mkDefault true;
      systemd = {
        enable = lib.mkDefault true;
        target = "hyprland-session.target";
      };
      settings = [
        {
          layer = "top";
          position = "top";
          height = 24;
          modules-left = ["hyprland/workspaces"];
          modules-center = ["hyprland/window"];
          modules-right = ["idle_inhibitor" "pulseaudio" "network" "bluetooth" "battery" "clock" "tray"];
          "hyprland/workspaces" = {
            format = "{icon}";
            on-scroll-up = "hyprctl dispatch workspace e+1";
            on-scroll-down = "hyprctl dispatch workspace e-1";
          };
        }
      ];
    };
  };
}
