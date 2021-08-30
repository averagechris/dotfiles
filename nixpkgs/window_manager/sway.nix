{ config, pkgs, ... }:

{
  config.wayland.windowManager.sway = {
    enable = true;
    config = {
      bars = [];
      gaps = {
        inner = 2;
        outer = 2;
        smartGaps = true;
      };
      input = {
        "*" = { natural_scroll = "enabled"; };
        "touchpad" = { tap = "enabled"; };
      };
      workspaceAutoBackAndForth = true;
    };
    wrapperFeatures = {
      base = true;
      gtk = true;
    };
  };

  config.programs.waybar = {
    enable = true;
    systemd.enable = true;
  };
}
