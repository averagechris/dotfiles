{ pkgs, config, ... }:

{
  config.programs.alacritty.enable = true;
  # register alacritty as sway's terminal if alacritty is installed 😀
  config.wayland.windowManager.sway.config.terminal = "${config.programs.alacritty.package}/bin/alacritty";
}
