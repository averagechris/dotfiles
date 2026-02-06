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
      # Try both gesture and mouse binding approaches for better compatibility

      # Gesture approach (may not work on all touchpads)
      gesture = [
        "3, horizontal, workspace"
      ];
    };
  };
}
