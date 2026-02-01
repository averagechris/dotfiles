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
      # New gesture syntax for hyprland 0.53.1
      # gesture = fingers, direction, action, options
      gesture = [
        "3, left, workspace, e-1"
        "3, right, workspace, e+1"
      ];
    };
  };
}
