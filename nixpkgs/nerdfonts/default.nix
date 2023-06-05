{
  pkgs,
  config,
  lib,
  ...
}: {
  config.xdg.dataFile.".fonts/nerdfonts" = lib.mkIf config.dotfiles.shell.nerdfonts.enable {
    source = pkgs.nerdfonts.override {
      inherit (config.dotfiles.shell.nerdfonts) fonts;
    };
  };
}
