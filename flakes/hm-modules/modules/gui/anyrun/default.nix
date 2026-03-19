# Anyrun launcher configuration
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
  subtleHex = lib.removePrefix "#" colors.subtle;
  terminalBin = config.dotfiles.gui.terminal.package;

  # Get anyrun packages from flake input if available
  hasAnyrunInput = inputs ? anyrun;
  anyrunPkgs =
    if hasAnyrunInput
    then inputs.anyrun.packages.${pkgs.stdenv.hostPlatform.system}
    else {};

  # Helper to get plugin path from package
  pluginPath = pkg: "${pkg}/lib/lib${lib.strings.replaceStrings ["-"] ["_"] pkg.pname}.so";
in {
  options.dotfiles.anyrun = {
    enable = lib.mkEnableOption "Anyrun launcher";
  };

  config = lib.mkIf (cfg.enable && hasAnyrunInput) {
    home.packages = [anyrunPkgs.anyrun-provider];

    programs.anyrun = {
      enable = true;
      package = anyrunPkgs.anyrun;
      config = {
        plugins = with anyrunPkgs; [
          (pluginPath applications)
          (pluginPath shell)
          (pluginPath rink)
          (pluginPath symbols)
        ];

        # Position and size - floating window, not fullscreen
        width.fraction = 0.35;
        y.fraction = 0.18;
        height.absolute = 280;
        margin = 0;

        # Behavior
        hidePluginInfo = true;
        closeOnClick = true;
        showResultsImmediately = false;
        maxEntries = 10;
        ignoreExclusiveZones = false;
        layer = "overlay";
      };

      extraConfigFiles."shell.ron".text = ''
        Config(
          prefix: ">",
          shell: ["${pkgs.bash}/bin/bash", "-lc"],
          placeholder: "Run shell command",
          show_icon: true,
        )
      '';

      # Main styling - clean and minimal
      extraCss = ''
        * {
          font-family: "JetBrains Mono", "FiraCode Nerd Font", monospace;
          font-size: 13px;
        }

        window {
          background: transparent;
        }

        box.main {
          background: ${colors.base};
          border: 1px solid ${colors.overlay};
          border-radius: 12px;
          box-shadow: 0 18px 36px rgba(0, 0, 0, 0.35);
          padding: 10px;
        }

        text {
          background: ${colors.surface};
          border-radius: 10px;
          color: ${colors.text};
          padding: 12px 14px;
          margin: 2px;
          font-size: 14px;
        }

        text:focus {
          outline: none;
        }

        text:empty {
          color: ${colors.subtle};
          background-image: url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='260' height='20'><text x='0' y='14' fill='%23${subtleHex}' font-family='Inter, sans-serif' font-size='12'>Type to search apps, calc, symbols…</text></svg>");
          background-repeat: no-repeat;
          background-position: 14px center;
        }

        box.matches {
          margin: 6px 2px 2px;
        }

        box.plugin:first-child {
          margin-top: 6px;
        }

        list.plugin {
          background: transparent;
        }

        .match {
          padding: 8px 16px;
          border-radius: 6px;
          color: ${colors.text};
        }

        .match:selected {
          background: ${colors.highlightMed};
        }

        .match:hover {
          background: ${colors.highlightLow};
        }

        label.match {
          color: ${colors.text};
        }

        label.match.description {
          color: ${colors.subtle};
          font-size: 11px;
        }

        label.plugin.info {
          color: ${colors.subtle};
          font-size: 10px;
        }
      '';

      # Configure applications plugin
      extraConfigFiles."applications.ron".text = ''
        Config(
          desktop_actions: true,
          max_entries: 8,
          terminal: Some(Terminal(
            command: "${terminalBin}/bin/${terminalBin.meta.mainProgram}",
            args: "-e {}",
          )),
        )
      '';
    };

    home.sessionVariables = {
      XDG_DATA_DIRS = lib.mkDefault "${config.home.homeDirectory}/.nix-profile/share:${config.home.profileDirectory}/share:/nix/var/nix/profiles/default/share:/run/current-system/sw/share";
    };
  };
}
