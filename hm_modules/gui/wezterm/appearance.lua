-- appearance.lua - Visual settings for wezterm
local wezterm = require 'wezterm'
local helpers = require 'wezterm_helpers'

local module = {}

--- Apply appearance settings to the WezTerm configuration
-- This function configures the visual appearance of WezTerm, including
-- colors, fonts, tab bar, and window decorations.
-- @param config table The WezTerm configuration table to modify
-- @return table The modified config with appearance settings applied
function module.apply(config)
  -- -----------------------------------------------
  -- COLOR SCHEME AND VISUAL APPEARANCE
  -- -----------------------------------------------
  -- Color scheme defined in Nix module
  config.color_scheme = 'Rose Pine Moon'
  
  -- Set padding to ensure tab bar is visible in tiling window managers
  -- @type {left: number, right: number, top: number, bottom: number}
  config.window_padding = {
    left = 0,
    right = 0,
    top = 0,
    bottom = 3, -- Modest padding for tab bar
  }
  
  -- -----------------------------------------------
  -- TAB BAR CONFIGURATION
  -- -----------------------------------------------
  config.use_fancy_tab_bar = false
  config.enable_tab_bar = true
  config.hide_tab_bar_if_only_one_tab = true
  config.tab_bar_at_bottom = true
  config.tab_and_split_indices_are_zero_based = true
  config.show_tab_index_in_tab_bar = false
  config.switch_to_last_active_tab_when_closing_tab = true
  
  -- Ensure tab bar works with tiling window managers
  config.enable_scroll_bar = false
  
  -- -----------------------------------------------
  -- GENERAL UI BEHAVIOR
  -- -----------------------------------------------
  config.notification_handling = "SuppressFromFocusedWindow"
  config.pane_focus_follows_mouse = true
  config.prefer_to_spawn_tabs = true
  config.quick_select_alphabet = "arstneiogmqwfpluyxcvdkhbjz"
  config.command_palette_rows = 15
  
  -- -----------------------------------------------
  -- FONT CONFIGURATION
  -- -----------------------------------------------
  -- @type table Font object with fallbacks
  config.font = wezterm.font_with_fallback {
    'JetBrains Mono',
    'Noto Color Emoji',
  }
  config.line_height = 1.0
  
  return config
end

--- DEPRECATED: Platform-specific appearance settings 
-- @deprecated This function is kept for compatibility but its functionality has been moved 
-- to the centralized helpers.apply_platform_settings(). Use that function instead.
-- @param config table The WezTerm configuration table
-- @return table The unmodified config (this function no longer changes anything)
function module.apply_platform_specific(config)
  wezterm.log_warning("appearance.apply_platform_specific() is deprecated. " ..
                     "Use helper.apply_platform_settings() instead.")
  return config
end

return module