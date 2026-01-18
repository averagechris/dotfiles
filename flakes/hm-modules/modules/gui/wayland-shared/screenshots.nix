{
  pkgs,
  lib,
  config,
  ...
}: {
  config = lib.mkIf config.dotfiles.gui.hyprland.enable {
    xdg.configFile."swappy/config".text = ''
      [Default]
      save_dir=$HOME/screenshots
      save_filename_format=%Y%m%d-%H%M%S-screenshot.png
      show_panel=false
      line_size=5
      text_size=20
      text_font=sans-serif
    '';
    home.packages = with pkgs; [
      grim
      slurp
      swappy
    ];
  };
}
