# Helix-Yazi Integration Module
#
# Key features:
# - Toggle a Yazi file picker pane from Helix with space.t.f
# - Inherit all Yazi config/keybindings while adding custom opener behavior
# - Open files in Helix from Yazi without closing the file browser
# - Proper pane management using WezTerm's capabilities
#
# Implementation notes:
# - We use recursiveUpdate to merge our custom configs with the base Yazi config
# - Environment variables are passed to preserve pane information
# - The :pipe-to Helix command is used to avoid output in the editor
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.dotfiles.helix-yazi-integration;

  # Generate TOML from Nix attrset
  tomlFormat = pkgs.formats.toml {};
  toTOML = config: tomlFormat.generate "config.toml" config;
in {
  options.dotfiles.helix-yazi-integration = {
    enable = mkEnableOption "Helix-Yazi integration via WezTerm";

    package = mkOption {
      type = types.package;
      default = pkgs.rustPlatform.buildRustPackage {
        pname = "helix-yazi-integration";
        version = "0.1.0";
        src = builtins.path {
          path = ./.;
          name = "helix-yazi-integration-source";
        };

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
          description = "Integration between Helix editor and Yazi file manager via WezTerm";
          license = licenses.mit;
        };
      };
      description = "The helix-yazi-integration package";
    };

    wezterm = mkOption {
      type = types.package;
      default = pkgs.wezterm;
      description = "WezTerm package to use for integration";
    };

    yazi = mkOption {
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
    # This option is kept for backward compatibility but will be ignored
    helixKeybinding = mkOption {
      type = types.str;
      default = "space.t.f";
      description = "Currently hardcoded to space.t.f - to be improved in future versions";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      cfg.package
    ];

    # Bind space.t.f to the picker command (the keybinding is hardcoded)
    programs.helix.settings = mkIf config.programs.helix.enable {
      keys.normal.space.t.f = ":pipe-to ${cfg.package}/bin/helix-yazi-integration open-picker --wezterm-path ${cfg.wezterm}/bin/wezterm --yazi-path ${cfg.yazi}/bin/yazi --yazi-config-dir ${config.home.homeDirectory}/.config/helix-yazi-integration --width ${toString cfg.pickerWidth} --side ${cfg.pickerSide}";
    };

    # Create a custom Yazi configuration directory for the integration
    xdg.configFile = {
      # Main Yazi config: standard settings plus our custom opener
      "helix-yazi-integration/yazi.toml" = mkIf config.programs.yazi.enable {
        source = toTOML (recursiveUpdate config.programs.yazi.settings {
          opener = {
            edit = [
              {run = "${cfg.package}/bin/helix-yazi-integration open-file \"$1\" --wezterm-path ${cfg.wezterm}/bin/wezterm";}
            ];
          };
        });
      };

      # Keymap file: all main keybindings plus our custom quit behavior
      "helix-yazi-integration/keymap.toml" = mkIf config.programs.yazi.enable {
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
              manager =
                baseKeymap.manager
                // {
                  keymap = [quitBinding] ++ baseKeymap.manager.keymap;
                };
            };
        in
          toTOML modifiedKeymap;
      };

      # Copy the theme configuration
      "helix-yazi-integration/theme.toml" = mkIf config.programs.yazi.enable {
        source = toTOML config.programs.yazi.theme;
      };
    };
  };
}
