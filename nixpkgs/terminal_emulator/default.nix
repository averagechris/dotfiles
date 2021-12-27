{ pkgs, config, ... }:

{
  config.programs.alacritty.enable = true;
  config.wayland.windowManager.sway.config.terminal = "${config.programs.alacritty.package}/bin/alacritty";
}
