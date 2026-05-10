{
  config,
  lib,
  ...
}: let
  hyprlandCfg = config.dotfiles.gui.hyprland;
  cfg = hyprlandCfg.waybar;
  fullBarSettings = {
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
  };

  trayOnlySettings = {
    name = "tray-only";
    layer = "top";
    position = "top";
    height = 24;
    exclusive = false;
    passthrough = false;
    fixed-center = false;
    margin-top = 4;
    margin-right = 8;
    modules-left = [];
    modules-center = [];
    modules-right = ["tray"];
    tray = {
      icon-size = 16;
      spacing = 8;
    };
  };
in {
  options.dotfiles.gui.hyprland.waybar.trayOnly.enable = lib.mkEnableOption "a tray-only Waybar StatusNotifier surface next to the Eww bar";

  # Enable Waybar when either the full bar or tray-only surface is requested.
  # tater keeps Eww as the primary bar and uses trayOnly as the real SNI host.
  config = lib.mkIf (hyprlandCfg.enable && (cfg.enable || cfg.trayOnly.enable)) {
    programs.waybar = {
      enable = lib.mkDefault true;
      systemd = {
        enable = lib.mkDefault true;
        targets = ["hyprland-session.target"];
      };
      settings = lib.optional cfg.enable fullBarSettings ++ lib.optional cfg.trayOnly.enable trayOnlySettings;
      style = lib.mkAfter ''
        window#waybar.tray-only {
          background: transparent;
          border: none;
          box-shadow: none;
          color: #e0def4;
        }

        window#waybar.tray-only #tray {
          background: rgba(25, 23, 36, 0.88);
          border: 1px solid rgba(196, 167, 231, 0.45);
          border-radius: 10px;
          padding: 3px 8px;
        }
      '';
    };
  };
}
