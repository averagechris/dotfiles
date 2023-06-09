{
  config,
  lib,
  ...
}: let
  xdgConfigHome = config.xdg.configHome;
  cfg = config.programs.alacritty;
in {
  config = with lib; {
    programs.alacritty.settings = {
      window.option_as_alt = "Both";
      font.size = mkDefault 16;
      import = [
        "${xdgConfigHome}/alacritty/themes/rose-pine.yml"
      ];
    };

    # https://github.com/rose-pine/alacritty/raw/main/dist/rose-pine-moon.yml
    xdg.configFile = mkIf cfg.enable {
      "alacritty/themes/rose-pine.yml".source = ./themes/alacritty-rose-pine.yml;
    };
  };
}
