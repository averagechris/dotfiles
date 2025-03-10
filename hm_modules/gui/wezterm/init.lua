-- init.lua for wezterm
-- Core helper functions for wezterm configuration
--
-- This module provides platform detection and platform-specific settings,
-- centralizing all OS-dependent configuration in one place.
-- It's imported as 'wezterm_helpers' in the configuration.

local wezterm = require 'wezterm'
local module = {}

-- Platform detection helpers
-- These functions determine which operating system WezTerm is running on

--- Detects if running on macOS
-- @return boolean True if running on macOS (Intel or Apple Silicon)
function module.is_macos()
  return wezterm.target_triple == 'x86_64-apple-darwin' or 
         wezterm.target_triple == 'aarch64-apple-darwin'
end

--- Detects if running on Linux
-- @return boolean True if running on any Linux distribution
function module.is_linux()
  return wezterm.target_triple == 'x86_64-unknown-linux-gnu' or
         wezterm.target_triple:find('linux') ~= nil
end

--- Detects if running on Windows
-- @return boolean True if running on Windows
function module.is_windows()
  return wezterm.target_triple:find('windows') ~= nil
end

--- Apply platform-specific settings to the WezTerm configuration
-- This is the central function for all OS-specific customizations.
-- It applies settings based on the detected operating system.
-- @param config table The WezTerm configuration table to modify
-- @return table The modified config with platform-specific settings applied
function module.apply_platform_settings(config)
  -- Create a platform detection object for cleaner conditionals
  -- @type {macos: boolean, linux: boolean, windows: boolean}
  local platform = {
    macos = module.is_macos(),
    linux = module.is_linux(),
    windows = module.is_windows(),
  }
  
  -- Platform-specific font size defaults
  if platform.macos then
    config.font_size = config.font_size or 13.0
  else
    config.font_size = config.font_size or 11.0
  end
  
  -- Platform-specific window decorations
  if platform.macos then
    -- macOS-specific settings
    config.native_macos_fullscreen_mode = true
    config.window_decorations = "RESIZE"
    config.macos_window_background_blur = 20
    
    -- Add macOS-specific keybindings using CMD instead of CTRL
    if config.keys then
      -- Add font size adjustment with CMD on macOS
      table.insert(config.keys, { key = '=', mods = 'CMD', action = wezterm.action.IncreaseFontSize })
      table.insert(config.keys, { key = '-', mods = 'CMD', action = wezterm.action.DecreaseFontSize })
      table.insert(config.keys, { key = '0', mods = 'CMD', action = wezterm.action.ResetFontSize })
    end
  elseif platform.windows then
    -- Windows-specific settings
    config.win32_system_backdrop = "Acrylic" 
    config.win32_acrylic_accent_color = { 0.15, 0.15, 0.15, 0.8 }
  elseif platform.linux then
    -- Linux-specific settings
    config.enable_wayland = true
    config.window_decorations = "RESIZE"
    -- Ensure tab bar works correctly with tiling window managers
    config.adjust_window_size_when_changing_font_size = false
  end
  
  wezterm.log_info("Applied platform-specific settings for: " .. 
                  (platform.macos and "macOS" or 
                   platform.windows and "Windows" or 
                   platform.linux and "Linux" or "Unknown"))
  
  return config
end

return module