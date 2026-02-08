# Hyprland animation configuration
{
  lib,
  config,
  ...
}: let
  cfg = config.dotfiles.gui.hyprland;
in {
  options.dotfiles.gui.hyprland.animations = {
    enable = lib.mkEnableOption "Enable Hyprland animations" // {default = true;};
  };

  config = lib.mkIf (cfg.enable && cfg.animations.enable) {
    wayland.windowManager.hyprland.settings = {
      animations = {
        enabled = true;
        bezier = [
          "smoothOut, 0.36, 0, 0.66, -0.56"
          "smoothIn, 0.25, 1, 0.5, 1"
          "overshot, 0.05, 0.9, 0.1, 1.1"
          "linear, 0, 0, 1, 1"
        ];
        animation = [
          "windows, 1, 4, overshot, slide"
          "windowsOut, 1, 4, smoothOut, slide"
          "windowsMove, 1, 4, smoothIn, slide"
          "border, 1, 10, default"
          "borderangle, 1, 100, linear, loop"
          "fade, 1, 4, smoothIn"
          "fadeDim, 1, 4, smoothIn"
          "workspaces, 1, 4, overshot, slidefade"
        ];
      };
    };
  };
}
