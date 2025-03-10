-- WezTerm configuration - Main entry point
-- Modular structure for better maintainability

local wezterm = require 'wezterm'
local act = wezterm.action

-- Try to load our helper functions
local helper
local helper_loaded, helper_or_error = pcall(function() return require('wezterm_helpers') end)
if not helper_loaded then
  wezterm.log_error("Failed to load wezterm_helpers module:", helper_or_error)
  -- If it fails, use a minimal implementation
  helper = {
    nested_keybindings = function(prefix, bindings)
      local result = {}
      for _, binding in ipairs(bindings) do
        if binding.key and binding.action then
          table.insert(result, {
            key = binding.key,
            mods = prefix,
            action = binding.action
          })
        end
      end
      return result
    end,
    with_escape_to_exit = function(bindings)
      table.insert(bindings, {
        key = 'Escape',
        action = wezterm.action.PopKeyTable,
      })
      return bindings
    end,
    setup_status_indicator = function(config)
      return config
    end,
    is_macos = function() 
      return wezterm.target_triple == 'x86_64-apple-darwin' or 
             wezterm.target_triple == 'aarch64-apple-darwin'
    end,
    is_linux = function()
      return wezterm.target_triple == 'x86_64-unknown-linux-gnu' or
             wezterm.target_triple:find('linux') ~= nil
    end,
    is_windows = function()
      return wezterm.target_triple:find('windows') ~= nil
    end
  }
else
  helper = helper_or_error
end

-- Try to load the keys module
local keys_module
local keys_loaded, keys_or_error = pcall(function() return require('keys') end)
if not keys_loaded then
  wezterm.log_error("Failed to load keys module, will use inline key definitions:", keys_or_error)
  -- We'll use the definitions directly in this file if the module is not available
  keys_module = nil
else
  keys_module = keys_or_error
end

-- Try to load the appearance module
local appearance_module
local appearance_loaded, appearance_or_error = pcall(function() return require('appearance') end)
if not appearance_loaded then
  wezterm.log_error("Failed to load appearance module, will use inline appearance settings:", appearance_or_error)
  -- We'll use the settings directly in this file if the module is not available
  appearance_module = nil
else
  appearance_module = appearance_or_error
end

-- Initialize the configuration
local config = wezterm.config_builder()

-- Set up event handlers
-- Show which key table is active in the status area
wezterm.on('update-right-status', function(window, pane)
  local name = window:active_key_table()
  if name then
    name = 'MODE: ' .. name
  end
  window:set_right_status(name or '')
end)

-- Clear key table stack when configuration is reloaded to avoid lingering key tables
wezterm.on('window-config-reloaded', function(window, pane)
  window:perform_action(act.ClearKeyTableStack, pane)
  wezterm.log_info('Config reloaded, cleared key table stack')
end)

-- Ensure unbound keys exit their key table and pass through to the terminal
wezterm.on('unbound-key-event', function(window, pane, key_event)
  local key_table = window:active_key_table()
  
  -- Only process events while in a key table
  if key_table then
    -- If escape is pressed, always exit the key table
    if key_event.key == 'Escape' then
      window:perform_action(act.PopKeyTable, pane)
      return true
    end
    
    -- For the leader key table, send the key and exit leader mode
    if key_table == 'leader' then
      if utf8.len(key_event.key) == 1 then
        window:perform_action(
          act.Multiple {
            act.SendKey { key = key_event.key },
            act.PopKeyTable,
          },
          pane
        )
        return true
      end
    end
    
    -- For window and tab management tables, just exit on unbound keys
    if key_table == 'window_management' or key_table == 'tab_management' then
      window:perform_action(act.PopKeyTable, pane)
      return true
    end
  end
  
  -- We didn't handle this event
  return false
end)

-- Reset any existing key tables at startup
wezterm.on('gui-startup', function(cmd)
  -- Log on startup to confirm the config loaded
  wezterm.log_info('Configuration loaded successfully')
end)

-- Define key tables - either from module or inline
if keys_module then
  -- Use the keys module if available
  config.key_tables = keys_module.get_key_tables()
  config.keys = keys_module.get_default_keys()
else
  -- Define inline if module not available
  config.key_tables = {
    -- Leader activation table for shift+space
    leader = {
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
    },
  
  -- Window management commands (shift+space w prefix)
  window_management = {
    -- Escape exits window mode
    { key = 'Escape', action = act.PopKeyTable },
    
    -- Window control actions
    { key = 'd', action = act.Multiple {
      act.CloseCurrentPane { confirm = true },
      act.PopKeyTable,
    }}, -- Close current window (with prompt)
    
    { key = 'f', action = act.Multiple {
      act.TogglePaneZoomState,
      act.PopKeyTable,
    }}, -- Toggle between current and stack layout
    
    { key = 'r', action = act.ActivateKeyTable { 
      name = 'resize_mode', 
      one_shot = false,
      replace_current = true
    }}, -- Enter window resize mode

    -- Window navigation using Colemak Mod-DH movement keys (mnei)
    { key = 'n', action = act.Multiple {
      act.ActivatePaneDirection 'Down',
      act.PopKeyTable,
    }}, -- Focus window below
    
    { key = 'e', action = act.Multiple {
      act.ActivatePaneDirection 'Up',
      act.PopKeyTable,
    }}, -- Focus window above
    
    { key = 'm', action = act.Multiple {
      act.ActivatePaneDirection 'Left',
      act.PopKeyTable,
    }}, -- Focus window to the left
    
    { key = 'i', action = act.Multiple {
      act.ActivatePaneDirection 'Right',
      act.PopKeyTable,
    }}, -- Focus window to the right

    -- Split creation commands
    { key = 's', action = act.Multiple {
      act.SplitVertical { domain = 'CurrentPaneDomain' },
      act.PopKeyTable,
    }}, -- Create horizontal split (stacked)
    
    { key = 'v', action = act.Multiple {
      act.SplitHorizontal { domain = 'CurrentPaneDomain' },
      act.PopKeyTable,
    }}, -- Create vertical split (side by side)

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
    }}, -- Swap with another window
  },

  -- Layout mode submenu
  layout_mode = {
    -- Escape exits layout mode
    { key = 'Escape', action = act.PopKeyTable },
    
    -- Layout options
    { key = 's', action = act.Multiple {
      act.PopKeyTable,
      act.PaneSelect { mode = 'Activate' } 
    }}, -- Side-by-side splits layout
    
    { key = 'S', mods = 'SHIFT', action = act.Multiple {
      act.PopKeyTable,
      act.PaneSelect { mode = 'Activate' }
    }}, -- Stacked splits layout
    
    { key = 't', action = act.Multiple {
      act.PopKeyTable,
      act.PaneSelect { mode = 'Activate' }
    }}, -- Tall layout
    
    { key = 'f', action = act.Multiple {
      act.PopKeyTable,
      act.PaneSelect { mode = 'Activate' }
    }}, -- Fat layout
    
    { key = 'g', action = act.Multiple {
      act.PopKeyTable,
      act.PaneSelect { mode = 'Activate' }
    }}, -- Grid layout
    
    { key = 'k', action = act.Multiple {
      act.PopKeyTable,
      act.TogglePaneZoomState
    }}, -- Stack layout
    
    { key = 'r', action = act.Multiple {
      act.PopKeyTable,
      act.RotatePanes 'Clockwise'
    }}, -- Rotate split orientation
  },

  -- Resize mode - stays active until Escape is pressed
  resize_mode = {
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
  },

  -- Tab management commands (shift+space t prefix)
  tab_management = {
    -- Explicit Escape to exit tab mode
    { key = 'Escape', action = act.PopKeyTable },
    
    -- Tab navigation - using Colemak movement keys
    { key = 'i', action = act.Multiple {
        act.ActivateTabRelative(1),
        act.PopKeyTable,
      }
    }, -- Go to next tab
    { key = 'm', action = act.Multiple {
        act.ActivateTabRelative(-1),
        act.PopKeyTable,
      }
    }, -- Go to previous tab

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
      }
    }, -- Rename current tab
    { key = 'n', action = act.Multiple {
        act.SpawnTab 'CurrentPaneDomain',
        act.PopKeyTable,
      }
    }, -- Create new tab
    { key = 'N', mods = 'SHIFT', action = act.Multiple {
        act.SpawnTab 'CurrentPaneDomain',
        act.ActivateTabRelative(-1),
        act.PopKeyTable,
      }
    }, -- Create and immediately go to new tab
    { key = 't', action = act.Multiple {
        act.ShowTabNavigator,
        act.PopKeyTable,
      }
    }, -- Open tab selector menu
    { key = 'd', action = act.Multiple {
        act.CloseCurrentTab { confirm = true },
        act.PopKeyTable,
      }
    }, -- Close current tab

    -- Direct tab selection by number
    { key = '1', action = act.Multiple {
        act.ActivateTab(0),
        act.PopKeyTable,
      }
    }, -- Go to first tab
    { key = '2', action = act.Multiple {
        act.ActivateTab(1),
        act.PopKeyTable,
      }
    }, -- Go to second tab
    { key = '3', action = act.Multiple {
        act.ActivateTab(2),
        act.PopKeyTable,
      }
    }, -- Go to third tab
    { key = '4', action = act.Multiple {
        act.ActivateTab(3),
        act.PopKeyTable,
      }
    }, -- Go to fourth tab
    { key = '5', action = act.Multiple {
        act.ActivateTab(4),
        act.PopKeyTable,
      }
    }, -- Go to fifth tab
    { key = '6', action = act.Multiple {
        act.ActivateTab(5),
        act.PopKeyTable,
      }
    }, -- Go to sixth tab
    { key = '7', action = act.Multiple {
        act.ActivateTab(6),
        act.PopKeyTable,
      }
    }, -- Go to seventh tab
    { key = '8', action = act.Multiple {
        act.ActivateTab(7),
        act.PopKeyTable,
      }
    }, -- Go to eighth tab
    { key = '9', action = act.Multiple {
        act.ActivateTab(8),
        act.PopKeyTable,
      }
    }, -- Go to ninth tab

    -- Escape from this mode
    { key = 'Escape', action = act.PopKeyTable },
  },
}

-- Main keybindings - only define the essential ones
config.keys = {
  -- Standard clipboard operations
  { key = 'c', mods = 'CTRL|SHIFT', action = act.CopyTo 'Clipboard' },
  { key = 'v', mods = 'CTRL|SHIFT', action = act.PasteFrom 'Clipboard' },
  { key = 'l', mods = 'CTRL|SHIFT', action = act.ShowDebugOverlay },

  -- Font size adjustment (platform specific)
  -- Linux
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

-- Apply appearance settings
if appearance_module then
  -- Use the appearance module if available
  appearance_module.apply(config)
  appearance_module.apply_platform_specific(config)
else
  -- Inline appearance settings
  -- Set the color scheme to match your kitty theme
  config.color_scheme = 'Rosé Pine Moon'

  -- General configuration settings
  config.window_decorations = "RESIZE"
  config.window_padding = {
    left = 0,
    right = 0,
    top = 0,
    bottom = 0,
  }

  -- Tab bar configuration
  config.use_fancy_tab_bar = false
  config.enable_tab_bar = true
  config.hide_tab_bar_if_only_one_tab = true
  config.tab_bar_at_bottom = true
  config.tab_and_split_indices_are_zero_based = true
  config.show_tab_index_in_tab_bar = false
  config.switch_to_last_active_tab_when_closing_tab = true

  -- Command palette and behavior settings
  config.command_palette_rows = 15
  config.notification_handling = "SuppressFromFocusedWindow"
  config.pane_focus_follows_mouse = true
  config.prefer_to_spawn_tabs = true
  config.quick_select_alphabet = "arstneiogmqwfpluyxcvdkhbjz"

  -- Font configuration
  config.font = wezterm.font_with_fallback {
    'JetBrains Mono',
    'Noto Color Emoji',
  }
  config.font_size = 11.0
  config.line_height = 1.0
  
  -- Platform-specific settings
  if helper.is_macos() then
    config.native_macos_fullscreen_mode = true
  end
end

-- Reset any existing key tables at startup
wezterm.on('gui-startup', function(cmd)
  -- Log on startup to confirm the config loaded
  wezterm.log_info('Configuration loaded successfully')
end)

return config