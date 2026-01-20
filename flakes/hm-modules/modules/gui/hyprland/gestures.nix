# Hyprland touchpad gesture configuration
{
  lib,
  config,
  ...
}: let
  cfg = config.dotfiles.gui.hyprland;
in {
  options.dotfiles.gui.hyprland.gestures = {
    enable = lib.mkEnableOption "Enable touchpad gestures" // {default = true;};
  };

  config = lib.mkIf (cfg.enable && cfg.gestures.enable) {
    wayland.windowManager.hyprland.settings = {
      gestures = {
        workspace_swipe = true;
        workspace_swipe_fingers = 3;
        workspace_swipe_distance = 300;
        workspace_swipe_invert = false;
        workspace_swipe_min_speed_to_force = 30;
        workspace_swipe_cancel_ratio = 0.5;
        workspace_swipe_create_new = true;
        workspace_swipe_forever = true;
      };
    };
  };
}
