{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
  nested = prefix: bindings: with lib.attrsets; mapAttrs' (k: v: nameValuePair "${prefix}>${k}" v) bindings;

  # All terminal keybindings sit behind a shift+space leader chord.
  # Prefer mnemonic bindings where the key hints at the action.
  prefixed = nested "shift+space";

  # tab prefix nests tab commands under `shift+space` as leaders
  # then `t`, so to make a new tab, i press `shift+space` then `t` then `n`
  tabp = nested "shift+space>t";

  # window prefix nests window commands under `shift+space` as leaders
  # then `w`, so to make a vertical split, i press `shift+space` then `w` then `v`
  windowp = nested "shift+space>w";

  # Shell application that shows kitty session info: current layout,
  # windows, tabs, and a shortcut reference. Runs in an overlay window.
  kitty-info = pkgs.writeShellApplication {
    name = "kitty-info";
    runtimeInputs = with pkgs; [jq coreutils gnused];
    text = ''
      set -e  # Exit on error

      echo -e "\033[1;36m===== Kitty Session Info =====\033[0m"
      echo

      # Get current layout - directly from kitty @ ls data
      echo -e "\033[1;33mCurrent Layout:\033[0m"
      kitty_data=$(kitty @ ls 2>/dev/null || echo '[]')
      layout_name=$(echo "$kitty_data" | jq -r 'try (.[0].tabs[0].layout) // "unknown"' 2>/dev/null || echo "unknown")
      echo "  Current layout: $layout_name"
      echo

      # Get window info - with error handling
      echo -e "\033[1;33mWindows:\033[0m"
      total=$(echo "$kitty_data" | jq -r "try (.[].tabs[].windows | length) // 0" 2>/dev/null || echo "Unknown")
      echo "  Total windows: $total"

      # List all windows with their titles
      window_list=$(echo "$kitty_data" | jq -r 'try (.[].tabs[].windows[] | "  • " + (.title // "Unknown") + " (" + (.id | tostring) + ")") // ""' 2>/dev/null)
      if [ -n "$window_list" ]; then
        echo "  Window list:"
        echo "$window_list"
      fi
      echo

      # Get previous window info (the one that was active before launching this overlay)
      # We'll use the window with id != 1 (assuming the overlay is typically id 1)
      # and the most recent activity time
      echo -e "\033[1;33mPrevious Active Window:\033[0m"
      prev_active_info=$(echo "$kitty_data" | jq -r 'try (
        .[].tabs[].windows |
        sort_by(.last_active) |
        reverse |
        .[0:2] |
        map(select(.id != 1)) |
        .[0] |
        "  Title: " + (.title // "Unknown") +
        "\n  ID: " + (.id | tostring) +
        "\n  Process: " + ((.foreground_processes[0].cmdline // ["Unknown"]) | join(" "))
      ) // "  Unable to determine previous window"' 2>/dev/null || echo "  Unable to determine previous window")

      if [ -z "$prev_active_info" ]; then
        echo "  No previous window found"
      else
        echo "$prev_active_info"
      fi
      echo

      # Get tab info - with error handling
      echo -e "\033[1;33mTabs:\033[0m"
      tab_info=$(echo "$kitty_data" | jq -r "try (.[].tabs[] | \"  \" + (if .is_focused then \">\" else \" \" end) + \" \" + (.title // \"Unknown\") + \" (\" + (.windows | length | tostring) + \" windows)\") // \"  None\"" 2>/dev/null || echo "  Unable to determine tab info")
      if [ -z "$tab_info" ]; then
        echo "  No tabs found"
      else
        echo "$tab_info"
      fi
      echo

      # Show system info
      echo -e "\033[1;33mSystem Info:\033[0m"
      echo "  Kitty version: $(kitty --version 2>/dev/null || echo "Unknown")"
      echo "  Terminal dimensions: $(stty size 2>/dev/null | awk '{print $2 "x" $1}' || echo "Unknown")"
      current_time=$(date "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "Unknown")
      echo "  Current time: $current_time"

      # Show keybinding help in groups for easier reading
      echo
      echo -e "\033[1;33mWindow Management:\033[0m"
      echo "  shift+space w v       - create vertical split (side by side)"
      echo "  shift+space w s       - create horizontal split (stacked)"
      echo "  shift+space w shift+d - detach window (pop out to new window)"
      echo "  shift+space w shift+s - swap with another window"

      echo -e "\033[1;33mLayout Controls:\033[0m"
      echo "  shift+space w l s       - switch to side-by-side layout"
      echo "  shift+space w l shift+s - switch to stacked layout"
      echo "  shift+space w l t       - switch to tall layout"
      echo "  shift+space w l f       - switch to fat layout"
      echo "  shift+space w l g       - switch to grid layout"
      echo "  shift+space w l k       - switch to stack layout"
      echo "  shift+space w l r       - rotate split"

      echo -e "\033[1;33mWindow Movement:\033[0m"
      echo "  shift+space w shift+e     - move window up"
      echo "  shift+space w shift+n     - move window down"
      echo "  shift+space w shift+m     - move window left"
      echo "  shift+space w shift+i     - move window right"
      echo "  shift+space w ctrl+shift+e - move window to top edge"
      echo "  shift+space w ctrl+shift+j - move window to bottom edge"
      echo "  shift+space w ctrl+shift+m - move window to left edge"
      echo "  shift+space w ctrl+shift+i - move window to right edge"

      echo
      echo -e "\033[1;32mPress any key to close this overlay...\033[0m"

      exit 0  # Always exit with success
    '';
  };
in {
  programs.kitty = {
    # Keyboard shortcut definitions
    # Uses a modal approach with shift+space as the primary prefix key
    # Organization:
    # - Basic clipboard shortcuts: ctrl+shift+c/v
    # - OS-specific font sizing shortcuts
    # - shift+space: General commands with further submenus
    #   - shift+space>t: Tab management
    #   - shift+space>w: Window/split management
    keybindings =
      {
        # Standard clipboard operations
        "ctrl+shift+c" = "copy_to_clipboard";
        "ctrl+shift+v" = "paste_from_clipboard";
      }
      // (
        # OS-specific font sizing shortcuts
        if isDarwin
        then {
          # macOS uses cmd key
          "cmd+plus" = "change_font_size current +2.0";
          "cmd+minus" = "change_font_size current -2.0";
          "cmd+0" = "change_font_size current 0";
        }
        else if isLinux
        then {
          # Linux uses ctrl+shift
          "ctrl+shift+=" = "change_font_size current +2.0";
          "ctrl+shift+minus" = "change_font_size current -2.0";
          "ctrl+shift+0" = "change_font_size current 0";
        }
        else {}
      )
      // (prefixed {
        c = "copy_to_clipboard";
        l = "load_config_file";
        v = "paste_from_clipboard";
        "f1" = "launch --type=overlay --stdin-source=@screen_scrollback hx";
        "m>m" = "create_marker";
        "m>shift+m" = "remove_marker";
        # Display kitty window/layout information in an overlay window
        "shift+/" = "launch --type=overlay sh -c '${kitty-info}/bin/kitty-info && read -n 1'";
      })
      // (windowp {
        # Window management commands (shift+space w prefix)

        # Window control actions
        d = "close_window_with_confirmation"; # Close current window (with prompt)
        f = "toggle_layout stack"; # Toggle between current and stack layout
        r = "start_resizing_window"; # Enter window resize mode

        # Window navigation using Colemak Mod-DH movement keys (mnei)
        n = "neighboring_window bottom"; # Focus window below
        e = "neighboring_window top"; # Focus window above
        m = "neighboring_window left"; # Focus window to the left
        i = "neighboring_window right"; # Focus window to the right
        # Split creation commands
        s = "launch --location=hsplit --cwd=current"; # Create horizontal split (stacked)
        v = "launch --location=vsplit --cwd=current"; # Create vertical split (side by side)

        # Layout management submenu (shift+space w l prefix)
        "l>s" = "goto_layout splits:split_axis=horizontal"; # Side-by-side splits layout
        "l>shift+s" = "goto_layout splits:split_axis=vertical"; # Stacked splits layout
        "l>t" = "goto_layout tall"; # Tall layout (full height on left)
        "l>f" = "goto_layout fat"; # Fat layout (full width on top)
        "l>g" = "goto_layout grid"; # Grid layout (equal cells)
        "l>k" = "goto_layout stack"; # Stack layout (only one window visible)
        "l>r" = "layout_action rotate"; # Rotate split orientation

        # Window movement commands with Colemak Mod-DH bindings (mnei)
        "shift+e" = "move_window up"; # Move window up
        "shift+n" = "move_window down"; # Move window down
        "shift+m" = "move_window left"; # Move window left
        "shift+i" = "move_window right"; # Move window right

        # Move the window to a screen edge with ctrl+shift plus movement keys
        "ctrl+shift+e" = "layout_action move_to_screen_edge top"; # Move to top edge
        "ctrl+shift+j" = "layout_action move_to_screen_edge bottom"; # Move to bottom edge (j instead of n due to conflict)
        "ctrl+shift+m" = "layout_action move_to_screen_edge left"; # Move to left edge
        "ctrl+shift+i" = "layout_action move_to_screen_edge right"; # Move to right edge

        # Additional window management actions
        "shift+d" = "detach_window"; # Pop current window out to new OS window
        "ctrl+n" = "new_window_with_cwd"; # Create new window with same working directory
        "shift+r" = "set_window_title"; # Rename current window
        "shift+s" = "swap_with_window"; # Swap positions with another window

        # Display kitty window/layout information in an overlay window
        "ctrl+shift+/" = "launch --type=overlay sh -c '${kitty-info}/bin/kitty-info && read -n 1'";
      })
      // (tabp {
        # Tab management commands (shift+space t prefix)

        # Tab navigation - using Colemak movement keys
        i = "next_tab"; # Go to next tab
        m = "prev_tab"; # Go to previous tab

        # Tab manipulation
        r = "set_tab_title"; # Rename current tab
        n = "new_tab"; # Create new tab
        N = "combine : new_tab : goto_tab -1"; # Create and immediately go to new tab
        t = "select_tab"; # Open tab selector menu
        d = "close_tab"; # Close current tab
        "shift+d" = "detach_tab"; # Move current tab to new OS window

        # Direct tab selection by number
        "1" = "goto_tab 1"; # Go to first tab
        "2" = "goto_tab 2"; # Go to second tab
        "3" = "goto_tab 3"; # Go to third tab
        "4" = "goto_tab 4"; # Go to fourth tab
        "5" = "goto_tab 5"; # Go to fifth tab
        "6" = "goto_tab 6"; # Go to sixth tab
        "7" = "goto_tab 7"; # Go to seventh tab
        "8" = "goto_tab 8"; # Go to eighth tab
        "9" = "goto_tab 9"; # Go to ninth tab
      });

    # General kitty terminal configuration settings
    settings = {
      # Input/control settings
      clear_all_shortcuts = true; # Start with no default shortcuts (we define our own)
      allow_remote_control = "socket-only"; # Enable remote control via socket
      listen_on = "unix:/tmp/main-kitty-socket"; # Socket path for remote control

      # OS-specific behaviors
      macos_option_as_alt = true; # Make Option key work as Alt on macOS
      macos_quit_when_last_window_closed = true; # Exit kitty when last window is closed on macOS

      # Layout configuration
      # Set default layout to splits with horizontal axis for reliable side-by-side splits
      enabled_layouts = "splits:split_axis=horizontal,stack,tall,fat";

      # Content handling
      scrollback_pager =
        # Pager for viewing scrollback history
        if config.programs.helix.enable
        then "hx" # Use helix if available
        else "scrollback_pager less --chop-long-lines --RAW-CONTROL-CHARS +INPUT_LINE_NUMBER";
      paste_actions = "quote-urls-at-prompt,confirm"; # Safety features when pasting content
      strip_trailing_spaces = "smart"; # Remove trailing whitespace on save

      # Appearance
      tab_bar_style = "powerline"; # Use powerline style for tab bar
    };
    # Theme configuration
    themeFile = "rose-pine-moon"; # Use the Rose Pine Moon color theme

    # Include external configuration file for additional settings
    extraConfig = ''
      include extra.kitty.conf
    '';
  };
}
