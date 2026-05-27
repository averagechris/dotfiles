{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.pi;
in {
  options.programs.pi = {
    enable = lib.mkEnableOption "Pi coding agent";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.pi;
      defaultText = lib.literalExpression "pkgs.pi";
      description = "Pi package to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [cfg.package];
  };
}
