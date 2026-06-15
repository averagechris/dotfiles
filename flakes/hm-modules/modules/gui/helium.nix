{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.programs.helium;
in {
  options.programs.helium = {
    enable = mkEnableOption "Helium browser";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.helium-bin;
      defaultText = lib.literalExpression "pkgs.helium-bin";
      description = "Helium package to install.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [cfg.package];

    xdg.mimeApps.defaultApplications = {
      "x-scheme-handler/http" = ["helium.desktop"];
      "x-scheme-handler/https" = ["helium.desktop"];
      "text/html" = ["helium.desktop"];
      "application/xhtml+xml" = ["helium.desktop"];
    };
  };
}
