-- keys.lua - Key bindings and key tables for wezterm
--
-- This module implements a modal keybinding system for WezTerm, similar to
-- Vim or Helix editor. The system uses a "leader key" (SHIFT+Space) to enter
-- a command mode, followed by additional keypresses to perform actions.
--
-- Key Tables:
-- - leader: Main command mode, accessed via SHIFT+Space
-- - window_management (w): Commands for working with panes/windows
-- - tab_management (t): Commands for working with tabs
-- - resize_mode (r): Commands for resizing panes
-- - layout_mode (l): Commands for managing layout
--
-- The keybindings use Colemak Mod-DH for navigation where possible:
-- - m: left
-- - n: down
-- - e: up
-- - i: right
--
-- Arrow keys are provided as alternatives where appropriate.

local wezterm = require 'wezterm'
local helpers = require 'wezterm_helpers'
local act = wezterm.action

local module = {}

--- Get the leader key table definition
-- The leader table contains the primary modal commands that are available
-- after pressing the leader key (SHIFT+Space).
-- @return table[] Array of keybinding definitions for the leader mode
function module.get_leader_keytable()
  return {
    -- Escape exits leader mode
    { key = 'Escape', action = act.PopKeyTable },
    
    -- Space key for passing through in leader mode
    { key = 'Space', action = act.Multiple {
      act.SendKey { key = 'Space' },
      act.PopKeyTable,
    }},
    
    -- Leader commands
    { key = 'l', action = act.Multiple {
      act.ReloadConfiguration,
      act.PopKeyTable,
    }},
    { key = 'c', action = act.Multiple {
      act.CopyTo 'Clipboard',
      act.PopKeyTable,
    }},
    { key = 'v', action = act.Multiple {
      act.PasteFrom 'Clipboard',
      act.PopKeyTable,
    }},
    
    -- Tab management activation
    { key = 't', action = act.ActivateKeyTable { 
      name = 'tab_management', 
      one_shot = false,
      replace_current = true 
    }},
    
    -- Window management activation
    { key = 'w', action = act.ActivateKeyTable { 
      name = 'window_management', 
      one_shot = false,
      replace_current = true 
    }},
  }
end

--- Get the window management key table
-- These keybindings are active when in window management mode,
-- which is activated via SHIFT+Space followed by 'w'.
-- Includes commands for pane navigation, splits, and layout.
-- @return table[] Array of keybinding definitions for window management mode
function module.get_window_keytable()
  return {
    -- Escape exits window mode
    { key = 'Escape', action = act.PopKeyTable },
    
    -- Window control actions
    { key = 'd', action = act.Multiple {
      act.CloseCurrentPane { confirm = true },
      act.PopKeyTable,
    }},
    
    { key = 'f', action = act.Multiple {
      act.TogglePaneZoomState,
      act.PopKeyTable,
    }},
    
    { key = 'r', action = act.ActivateKeyTable { 
      name = 'resize_mode', 
      one_shot = false,
      replace_current = true
    }},

    -- Window navigation using Colemak Mod-DH movement keys (mnei)
    { key = 'n', action = act.Multiple {
      act.ActivatePaneDirection 'Down',
      act.PopKeyTable,
    }},
    
    { key = 'e', action = act.Multiple {
      act.ActivatePaneDirection 'Up',
      act.PopKeyTable,
    }},
    
    { key = 'm', action = act.Multiple {
      act.ActivatePaneDirection 'Left',
      act.PopKeyTable,
    }},
    
    { key = 'i', action = act.Multiple {
      act.ActivatePaneDirection 'Right',
      act.PopKeyTable,
    }},

    -- Split creation commands
    { key = 's', action = act.Multiple {
      act.SplitVertical { domain = 'CurrentPaneDomain' },
      act.PopKeyTable,
    }},
    
    { key = 'v', action = act.Multiple {
      act.SplitHorizontal { domain = 'CurrentPaneDomain' },
      act.PopKeyTable,
    }},

    -- Layout management submenu
    { key = 'l', action = act.ActivateKeyTable { 
      name = 'layout_mode', 
      one_shot = true,
      replace_current = true 
    }},

    -- Window movement commands
    { key = 'S', mods = 'SHIFT', action = act.Multiple {
      act.PaneSelect { mode = 'SwapWithActive' },
      act.PopKeyTable,
    }},
  }
end

--- Get the layout mode key table
-- These keybindings are active when in layout management mode,
-- which is activated via window management mode followed by 'l'.
-- This mode includes commands for selecting, zooming, and rotating panes.
-- @return table[] Array of keybinding definitions for layout mode
function module.get_layout_keytable()
  return {
    -- Escape exits layout mode
    { key = 'Escape', action = act.PopKeyTable },
    
    -- Layout options
    { key = 's', action = act.Multiple {
      act.PopKeyTable,
      act.PaneSelect { mode = 'Activate' } 
    }},
    
    { key = 'S', mods = 'SHIFT', action = act.Multiple {
      act.PopKeyTable,
      act.PaneSelect { mode = 'Activate' }
    }},
    
    { key = 't', action = act.Multiple {
      act.PopKeyTable,
      act.PaneSelect { mode = 'Activate' }
    }},
    
    { key = 'f', action = act.Multiple {
      act.PopKeyTable,
      act.PaneSelect { mode = 'Activate' }
    }},
    
    { key = 'g', action = act.Multiple {
      act.PopKeyTable,
      act.PaneSelect { mode = 'Activate' }
    }},
    
    { key = 'k', action = act.Multiple {
      act.PopKeyTable,
      act.TogglePaneZoomState
    }},
    
    { key = 'r', action = act.Multiple {
      act.PopKeyTable,
      act.RotatePanes 'Clockwise'
    }},
  }
end

--- Get the resize mode key table
-- These keybindings are active when in resize mode,
-- which is activated via window management mode followed by 'r'.
-- This mode remains active until explicitly exited, allowing for
-- continuous pane resizing. Uses Colemak mod-DH navigation keys.
-- @return table[] Array of keybinding definitions for resize mode
function module.get_resize_keytable()
  return {
    -- Escape exits resize mode
    { key = 'Escape', action = act.PopKeyTable },
    
    -- Using Colemak Mod-DH movement keys (mnei)
    { key = 'e', action = act.AdjustPaneSize { 'Up', 1 } },
    { key = 'n', action = act.AdjustPaneSize { 'Down', 1 } },
    { key = 'm', action = act.AdjustPaneSize { 'Left', 1 } },
    { key = 'i', action = act.AdjustPaneSize { 'Right', 1 } },

    -- Arrow keys as alternatives
    { key = 'UpArrow', action = act.AdjustPaneSize { 'Up', 1 } },
    { key = 'DownArrow', action = act.AdjustPaneSize { 'Down', 1 } },
    { key = 'LeftArrow', action = act.AdjustPaneSize { 'Left', 1 } },
    { key = 'RightArrow', action = act.AdjustPaneSize { 'Right', 1 } },
  }
end

--- Get the tab management key table
-- These keybindings are active when in tab management mode,
-- which is activated via SHIFT+Space followed by 't'.
-- Includes commands for creating, navigating, and closing tabs,
-- as well as direct tab selection via numbers.
-- @return table[] Array of keybinding definitions for tab management mode
function module.get_tab_keytable()
  return {
    -- Escape exits tab mode
    { key = 'Escape', action = act.PopKeyTable },
    
    -- Tab navigation - using Colemak movement keys
    { key = 'i', action = act.Multiple {
      act.ActivateTabRelative(1),
      act.PopKeyTable,
    }},
    
    { key = 'm', action = act.Multiple {
      act.ActivateTabRelative(-1),
      act.PopKeyTable,
    }},

    -- Tab manipulation
    { key = 'r', action = act.Multiple {
      act.PromptInputLine {
        description = 'Enter new name for tab',
        action = wezterm.action_callback(function(window, pane, line)
          if line then
            window:active_tab():set_title(line)
          end
        end),
      },
      act.PopKeyTable,
    }},
    
    { key = 'n', action = act.Multiple {
      act.SpawnTab 'CurrentPaneDomain',
      act.PopKeyTable,
    }},
    
    { key = 'N', mods = 'SHIFT', action = act.Multiple {
      act.SpawnTab 'CurrentPaneDomain',
      act.ActivateTabRelative(-1),
      act.PopKeyTable,
    }},
    
    { key = 't', action = act.Multiple {
      act.ShowTabNavigator,
      act.PopKeyTable,
    }},
    
    { key = 'd', action = act.Multiple {
      act.CloseCurrentTab { confirm = true },
      act.PopKeyTable,
    }},

    -- Direct tab selection by number
    { key = '1', action = act.Multiple {
      act.ActivateTab(0),
      act.PopKeyTable,
    }},
    
    { key = '2', action = act.Multiple {
      act.ActivateTab(1),
      act.PopKeyTable,
    }},
    
    { key = '3', action = act.Multiple {
      act.ActivateTab(2),
      act.PopKeyTable,
    }},
    
    { key = '4', action = act.Multiple {
      act.ActivateTab(3),
      act.PopKeyTable,
    }},
    
    { key = '5', action = act.Multiple {
      act.ActivateTab(4),
      act.PopKeyTable,
    }},
    
    { key = '6', action = act.Multiple {
      act.ActivateTab(5),
      act.PopKeyTable,
    }},
    
    { key = '7', action = act.Multiple {
      act.ActivateTab(6),
      act.PopKeyTable,
    }},
    
    { key = '8', action = act.Multiple {
      act.ActivateTab(7),
      act.PopKeyTable,
    }},
    
    { key = '9', action = act.Multiple {
      act.ActivateTab(8),
      act.PopKeyTable,
    }},
  }
end

--- Get all key tables combined
-- This function aggregates all the different key tables into a single table
-- for WezTerm to use. This is the main function called from the configuration.
-- @return table A mapping of key table names to key bindings
function module.get_key_tables()
  return {
    leader = module.get_leader_keytable(),
    window_management = module.get_window_keytable(),
    layout_mode = module.get_layout_keytable(),
    resize_mode = module.get_resize_keytable(),
    tab_management = module.get_tab_keytable(),
  }
end

--- Get default global key bindings
-- Returns the list of global keybindings that are always active.
-- Platform-specific keybindings are added by helper.apply_platform_settings().
-- @return table[] A list of keybinding definitions
function module.get_default_keys()
  -- Default keybindings that are used across all platforms
  -- @type {{key: string, mods: string, action: table}[]}
  local keys = {
    -- Standard clipboard operations
    { key = 'c', mods = 'CTRL|SHIFT', action = act.CopyTo 'Clipboard' },
    { key = 'v', mods = 'CTRL|SHIFT', action = act.PasteFrom 'Clipboard' },
    { key = 'l', mods = 'CTRL|SHIFT', action = act.ShowDebugOverlay },

    -- Font size adjustment (Linux and Windows)
    { key = '=', mods = 'CTRL|SHIFT', action = act.IncreaseFontSize },
    { key = '-', mods = 'CTRL|SHIFT', action = act.DecreaseFontSize },
    { key = '0', mods = 'CTRL|SHIFT', action = act.ResetFontSize },

    -- LEADER KEY SETUP - THE MOST IMPORTANT PART
    -- This activates leader mode with shift+space
    { key = 'Space', mods = 'SHIFT', action = act.ActivateKeyTable { 
      name = 'leader', 
      one_shot = true, 
      replace_current = true 
    }},
  }
  
  -- Platform-specific keybindings are now handled in helpers.apply_platform_settings
  -- to centralize platform-specific code
  
  return keys
end

return module