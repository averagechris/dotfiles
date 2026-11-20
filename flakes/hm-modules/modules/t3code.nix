{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  t3code = inputs.t3-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.t3code;
in {
  programs.t3code = {
    enable = true;
    package = t3code;
    userSettings.providerInstances.opencode = {
      driver = "opencode";
      enabled = true;
      config = {
        enabled = true;
        binaryPath = lib.getExe config.programs.opencode.package;
      };
    };
  };

  # The upstream AppImage keeps its desktop entry outside usr/share, which
  # the Nix package copies. Register it with the equivalent launcher settings.
  xdg.desktopEntries.t3code = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    name = "T3 Code";
    exec = "${lib.getExe t3code} %U";
    icon = "t3code";
    categories = ["Development"];
    mimeType = ["x-scheme-handler/t3code" "x-scheme-handler/t3code-dev"];
    settings.StartupWMClass = "com.t3tools.T3Code";
  };
}
