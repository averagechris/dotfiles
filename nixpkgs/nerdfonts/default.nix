{pkgs, ...}: {
  config.xdg.dataFile.".fonts/nerdfonts" = {
    source = pkgs.nerdfonts.override {
      fonts = [
        "FiraCode"
        "DroidSansMono"
        "Overpass"
      ];
    };
  };
}
