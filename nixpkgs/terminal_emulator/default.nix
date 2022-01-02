{ pkgs, config, ... }:

{
  config.programs.alacritty = {
    enable = true;
    settings = {
      font.normal.family = "SourceCodePro";
      font.bold.family = "SourceCodePro";
      font.italic.family = "SourceCodePro";
      font.bold_italic.family = "SourceCodePro";
      font.size = 16;
    };
  };
  config.wayland.windowManager.sway.config.terminal = "${config.programs.alacritty.package}/bin/alacritty";
}
