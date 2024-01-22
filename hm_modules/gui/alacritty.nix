{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  xdgConfigHome = config.xdg.configHome;
  cfg = config.programs.alacritty;
in {
  config = with lib; {
    programs.alacritty.settings =
      {
        font.size = mkDefault 16;
        import = [
          "${xdgConfigHome}/alacritty/themes/rose-pine.toml"
        ];
      }
      // (
        if isLinux
        then {}
        else {window.option_as_alt = "Both";}
      );

    # https://github.com/rose-pine/alacritty/raw/main/dist/rose-pine-moon.yml
    xdg.configFile = mkIf cfg.enable {
      "alacritty/themes/rose-pine.toml".source = ./themes/alacritty-rose-pine.toml;
    };
  };
}
