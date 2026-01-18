# Helix Terminal Tools Module
#
# This module provides integration between Helix editor and terminal tools:
# 1. Yazi file manager integration for file browsing
#
# Implementation notes:
# - Uses the same Rust binary with multiple subcommands
# - Both integrations use WezTerm for terminal pane management
# - Maintains existing Yazi functionality but generalizes the codebase
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  inherit (lib) mkIf mkMerge mkOption mkEnableOption types;
  cfg = config.dotfiles.helix-terminal-tools;

  # Generate TOML from Nix attrset
  tomlFormat = pkgs.formats.toml {};
  toTOML = config: tomlFormat.generate "config.toml" config;
in {
  options.dotfiles.helix-terminal-tools = {
    enable = mkEnableOption "Helix terminal tools integration (Yazi file manager)";

    package = mkOption {
      type = types.package;
      default = pkgs.rustPlatform.buildRustPackage {
        pname = "helix-terminal-tools";
        version = "0.1.0";
        src = ./.;

        cargoLock = {
          lockFile = ./Cargo.lock;
          outputHashes = {};
        };

        nativeBuildInputs = with pkgs; [
          pkg-config
        ];

        buildInputs = with pkgs; [
          openssl
        ];

        meta = {
          description = "Integration tools for Helix with terminal applications (Yazi)";
          license = licenses.mit;
        };
      };
      description = "The helix-terminal-tools package";
    };

    wezterm = mkOption {
      type = types.package;
      default = pkgs.wezterm;
      description = "WezTerm package to use for integration";
    };

    yazi = {
      enable = mkEnableOption "Yazi file manager integration";

      package = mkOption {
        type = types.package;
        default = pkgs.yazi;
        description = "Yazi package to use for integration";
      };

      # Picker configuration
      pickerWidth = mkOption {
        type = types.int;
        default = 30;
        description = "Width of the file picker pane as a percentage";
      };

      pickerSide = mkOption {
        type = types.enum ["left" "right"];
        default = "left";
        description = "Side of the screen to place the file picker";
      };

      # Note: We're hardcoding the keybinding for now to space.t.f
      helixKeybinding = mkOption {
        type = types.str;
        default = "space.t.f";
        description = "Currently hardcoded to space.t.f - to be improved in future versions";
      };
    };
  };

  config = mkIf cfg.enable {
    # Add the package to the user's packages
    home.packages = [
      cfg.package
    ];

    # Configure Helix settings with merged configurations for Yazi and
    programs.helix.settings = mkMerge [
      # Yazi integration settings
      (mkIf (config.programs.helix.enable && cfg.yazi.enable) {
        keys.normal = {
          space.t.f = ":pipe-to ${cfg.package}/bin/helix-terminal-tools open-picker --wezterm-path ${cfg.wezterm}/bin/wezterm --yazi-path ${cfg.yazi.package}/bin/yazi --yazi-config-dir ${config.home.homeDirectory}/.config/helix-terminal-tools/yazi --width ${toString cfg.yazi.pickerWidth} --side ${cfg.yazi.pickerSide}";

          # Add git UI keybinding
          space.g.g = ":sh ${cfg.wezterm}/bin/wezterm cli split-pane --top git ui";

          # Add terminal pane management/navigation commands
          space.o = {
            g = ":sh ${cfg.wezterm}/bin/wezterm cli split-pane --top git ui";
            h = ":sh ${cfg.wezterm}/bin/wezterm cli split-pane --bottom";
            v = ":sh ${cfg.wezterm}/bin/wezterm cli split-pane --right";
            t = ":sh ${cfg.wezterm}/bin/wezterm cli split-pane --bottom";
            T = ":sh ${cfg.wezterm}/bin/wezterm cli spawn --new-window";
            tab = ":sh ${cfg.wezterm}/bin/wezterm cli spawn --new-tab";
          };

          # WezTerm pane navigation
          space.k = {
            f = ":sh ${cfg.wezterm}/bin/wezterm cli toggle-pane-zoom";
            n = ":sh ${cfg.wezterm}/bin/wezterm cli activate-pane-direction down";
            e = ":sh ${cfg.wezterm}/bin/wezterm cli activate-pane-direction up";
            m = ":sh ${cfg.wezterm}/bin/wezterm cli activate-pane-direction left";
            i = ":sh ${cfg.wezterm}/bin/wezterm cli activate-pane-direction right";
          };
        };
      })
    ];

    # Create a custom Yazi configuration directory for the integration
    # This allows us to customize Yazi's behavior when launched from Helix
    xdg.configFile = mkIf cfg.yazi.enable {
      # Main Yazi config - inherits from the standard Yazi config and adds our custom opener
      "helix-terminal-tools/yazi/yazi.toml" = mkIf config.programs.yazi.enable {
        # Copy the entire settings from the main Yazi config and then add our custom opener
        source = toTOML (recursiveUpdate config.programs.yazi.settings {
          opener = {
            edit = [
              {run = "${cfg.package}/bin/helix-terminal-tools open-file \"$1\" --wezterm-path ${cfg.wezterm}/bin/wezterm";}
            ];
          };
        });
      };

      # Keymap file - inherit all keybindings from main config and add our custom quit behavior
      "helix-terminal-tools/yazi/keymap.toml" = mkIf config.programs.yazi.enable {
        source = let
          # Start with the base keymap configuration
          baseKeymap = config.programs.yazi.keymap;

          # Define our custom quit binding
          quitBinding = {
            on = ["q"];
            run = "quit";
            desc = "Quit and return to Helix";
          };

          # Create a modified keymap by adding our custom quit binding at the beginning
          # This ensures it takes precedence over any existing 'q' binding
          modifiedKeymap =
            baseKeymap
            // {
              mgr =
                baseKeymap.mgr
                // {
                  keymap = [quitBinding] ++ baseKeymap.mgr.keymap;
                };
            };
        in
          toTOML modifiedKeymap;
      };

      # Copy the theme configuration
      "helix-terminal-tools/yazi/theme.toml" = mkIf config.programs.yazi.enable {
        source = toTOML config.programs.yazi.theme;
      };
    };
  };
}
