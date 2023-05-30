{config, ...}: {
  config.programs.alacritty = {
    enable = true;
    settings = {
      # font.normal.family = "SourceCodePro";
      # font.bold.family = "SourceCodePro";
      # font.italic.family = "SourceCodePro";
      # font.bold_italic.family = "SourceCodePro";
      font.size = 16;
      import = [
        # TODO this should map from any theme file in ./themes/
        "${config.xdg.configHome}/alacritty/themes/rose-pine.yml"
      ];
    };
  };
  config.wayland.windowManager.sway.config.terminal = "${config.programs.alacritty.package}/bin/alacritty";
  # https://github.com/rose-pine/alacritty/raw/main/dist/rose-pine-moon.yml
  config.xdg.configFile."alacritty/themes/rose-pine.yml".source = ./themes/rose-pine.yml;
}
