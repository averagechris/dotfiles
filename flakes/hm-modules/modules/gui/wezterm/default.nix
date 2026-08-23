# WezTerm Home Manager Module
#
# Configures WezTerm with Lua modules copied to XDG_CONFIG_HOME and
# loaded from there rather than from the Nix store.
#
# Key features:
# - Modal keybinding system (SHIFT+Space as leader key)
# - Platform-specific settings handled automatically
# - Experimental prototyping system for ad-hoc changes
{
  config,
  lib,
  ...
}: {
  options.dotfiles.wezterm = {
    enable = lib.mkEnableOption "WezTerm terminal emulator configuration";
  };

  config = lib.mkIf config.dotfiles.wezterm.enable {
    programs.wezterm = {
      enable = true;

      extraConfig = ''
        -- Configure module loading path to find our modules
        package.path = package.path .. ";" .. wezterm.home_dir .. "/.config/wezterm/?.lua"

        -- Load required modules - no fallbacks as these should always be available
        -- @type {is_macos: function, is_linux: function, is_windows: function, apply_platform_settings: function}
        local helper = require("wezterm_helpers")

        -- @type {get_default_keys: function, get_key_tables: function}
        local keys = require("keys")

        -- @type {apply: function}
        local appearance = require("appearance")

        -- Initialize configuration object
        -- @type table WezTerm configuration table with defaults pre-populated
        local config = wezterm.config_builder()

        -- Apply configuration from our modules
        config.key_tables = keys.get_key_tables()
        config.keys = keys.get_default_keys()
        appearance.apply(config)

        -- Apply platform-specific settings from our centralized helper
        helper.apply_platform_settings(config)

        -- Set up event handlers for key tables
        -- Update status bar to show current key table (mode)
        -- @param window table The WezTerm window object
        -- @param pane table The active pane object
        wezterm.on("update-right-status", function(window, pane)
          -- @type string|nil The name of the active key table, or nil if none
          local name = window:active_key_table()
          if name then
            name = "MODE: " .. name
          end
          window:set_right_status(name or "")
        end)

        -- Clear key table stack when configuration is reloaded
        -- @param window table The WezTerm window object
        -- @param pane table The active pane object
        wezterm.on("window-config-reloaded", function(window, pane)
          -- Clear any active key tables to avoid them getting stuck
          window:perform_action(wezterm.action.ClearKeyTableStack, pane)
          wezterm.log_info("Config reloaded, cleared key table stack")
        end)

        -- Load prototyping.lua if it exists (for adhoc experimentation)
        do
          -- Use a do block to isolate variables
          local prototype_path = wezterm.home_dir .. "/.config/wezterm/prototyping.lua"

          -- Check if the file exists
          local file_exists = io.open(prototype_path, "r") ~= nil
          if not file_exists then
            -- No prototype file found, that's OK
            wezterm.log_info("No prototype config found at " .. prototype_path)
          else
            wezterm.log_info("Found prototyping.lua at " .. prototype_path)

            -- Use dofile to execute the file with proper error handling
            -- dofile is the most straightforward way to load a Lua file
            local success, result = pcall(function()
              return dofile(prototype_path)
            end)

            if success then
              if type(result) == "table" then
                wezterm.log_info("Successfully loaded prototyping module")

                -- Apply any direct settings from the module
                -- @type number Count of settings applied from the prototype
                local applied_settings = 0

                -- Loop through all keys in the prototype and apply them to config
                for key, value in pairs(result) do
                  if key ~= "apply" then
                    -- Apply each setting to override the configuration
                    -- @type any The value to assign to the config key
                    config[key] = value
                    applied_settings = applied_settings + 1
                    wezterm.log_info("Applied setting: " .. key)
                  end
                end

                -- Call the apply function if it exists
                if type(result.apply) == "function" then
                  wezterm.log_info("Calling prototype apply() function")
                  local apply_success, apply_error = pcall(function()
                    result.apply(config)
                  end)

                  if apply_success then
                    wezterm.log_info("Successfully applied prototype function")
                  else
                    wezterm.log_error("Error in prototype apply(): " .. tostring(apply_error))
                  end
                end

                if applied_settings == 0 and type(result.apply) ~= "function" then
                  wezterm.log_info("No prototype settings found to apply - " ..
                                 "uncomment some settings in the file to test them")
                end
              else
                -- Failed to load as table
                wezterm.log_error("Prototype file must return a table, got: " .. type(result))
              end
            else
              -- File couldn't be executed
              wezterm.log_error("Error loading prototype file: " .. tostring(result))
            end
          end
        end

        -- Force WezTerm to use X11/XWayland (disable native Wayland frontend)
        config.enable_wayland = false

        return config
      '';

      # Define the colorScheme directly to avoid conflicts with Home Manager
      # This overrides any file-based scheme with the same name
      colorSchemes = {
        "Rose Pine Moon" = {
          ansi = [
            "#393552"
            "#eb6f92"
            "#9ccfd8"
            "#f6c177"
            "#3e8fb0"
            "#c4a7e7"
            "#ea9a97"
            "#e0def4"
          ];
          brights = [
            "#6e6a86"
            "#eb6f92"
            "#9ccfd8"
            "#f6c177"
            "#3e8fb0"
            "#c4a7e7"
            "#ea9a97"
            "#e0def4"
          ];
          background = "#232136";
          cursor_bg = "#e0def4";
          cursor_border = "#e0def4";
          cursor_fg = "#232136";
          foreground = "#e0def4";
          selection_bg = "#44415a";
          selection_fg = "#e0def4";
        };
      };
    };

    # Copy our module files to .config/wezterm where they can be loaded
    xdg.configFile = {
      # Core helper module (platform detection, etc.)
      "wezterm/wezterm_helpers.lua".source = ./init.lua;

      # Keybinding system with modal interface
      "wezterm/keys.lua".source = ./keys.lua;

      # Visual appearance settings
      "wezterm/appearance.lua".source = ./appearance.lua;

      # Example file for ad-hoc configuration experiments
      "wezterm/prototyping.lua.example".source = ./prototyping.lua.example;

      # README with documentation
      "wezterm/README.md".source = ./README.md;

      # Color scheme is defined directly in colorSchemes above
    };
  };
}
