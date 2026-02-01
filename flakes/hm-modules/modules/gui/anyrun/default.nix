# Anyrun launcher configuration with Rose Pine Moon theme
#
# Note: This module requires the anyrun flake input to be available.
# The host flake should have:
#   anyrun.url = "github:anyrun-org/anyrun";
# And it will be passed via extraSpecialArgs.inputs
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.dotfiles.anyrun;
  inherit (config.dotfiles.gui.hyprland.theme) colors;

  # Get anyrun packages from flake input if available
  hasAnyrunInput = inputs ? anyrun;
  anyrunPkgs =
    if hasAnyrunInput
    then inputs.anyrun.packages.${pkgs.stdenv.hostPlatform.system}
    else {};
in {
  options.dotfiles.anyrun = {
    enable = lib.mkEnableOption "Anyrun launcher";
  };

  config = lib.mkIf (cfg.enable && hasAnyrunInput) {
    programs.anyrun = {
      enable = true;
      config = {
        plugins = with anyrunPkgs; [
          applications
          shell
          rink # Calculator
          symbols
          stdin
        ];

        width.fraction = 0.3;
        y.fraction = 0.2;
        hidePluginInfo = true;
        closeOnClick = true;
        showResultsImmediately = true;
        maxEntries = 10;
      };

      extraCss = ''
        /* Rose Pine Moon theme for Anyrun */
        * {
          font-family: "Inter", sans-serif;
        }

        #window {
          background: transparent;
        }

        #main {
          background: ${colors.base};
          border: 2px solid ${colors.overlay};
          border-radius: 12px;
        }

        #entry {
          background: ${colors.surface};
          border-radius: 8px;
          padding: 12px;
          color: ${colors.text};
        }

        #entry:focus {
          border: none;
          box-shadow: none;
        }

        #match {
          padding: 8px 12px;
          border-radius: 6px;
          color: ${colors.text};
        }

        #match:selected {
          background: ${colors.overlay};
        }

        #match:hover {
          background: ${colors.highlightMed};
        }

        #plugin {
          background: transparent;
          padding: 4px;
        }
      '';
    };
  };
}
