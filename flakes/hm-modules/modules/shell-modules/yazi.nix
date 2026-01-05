# Yazi terminal file manager configuration module
# Configures Yazi with Colemak-friendly keybindings and custom key sequences
# See https://yazi-rs.github.io/docs/configuration/keymap for keybindings documentation
# See https://yazi-rs.github.io/docs/configuration/yazi for general configuration
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  cfg = config.dotfiles.yazi;
in {
  options.dotfiles.yazi = {
    enable = mkEnableOption "Yazi terminal file manager with Colemak keybindings";
  };

  config = mkIf cfg.enable {
    programs.yazi = {
      enable = true;
      enableZshIntegration = lib.mkDefault config.programs.zsh.enable;
      enableBashIntegration = lib.mkDefault config.programs.bash.enable;

      # General settings for appearance and behavior
      settings = {
        # File manager panel configuration
        mgr = {
          show_hidden = false; # Don't show hidden files by default (toggle with H)
          sort_by = "natural"; # Natural sort order (1.txt, 2.txt, 10.txt)
          sort_dir_first = true; # Show directories before files
          sort_reverse = false; # Normal sort order (not reversed)
          ratio = [1 4 3]; # Panel ratio: [directories, files, preview]
          linemode = "size"; # Show file sizes in the listing
        };

        # Preview panel configuration
        preview = {
          max_height = 900; # Maximum preview height in pixels
          max_width = 600; # Maximum preview width in pixels
          tab_size = 2; # Tab size in spaces for text previews
        };
      };

      # Key binding configuration
      # Key binding summary:
      # - Navigation: Colemak MNEI instead of HJKL (n=down, e=up, m=left/back, i=right/enter)
      # - File selection: <Space>=toggle and move down, u=unselect current item
      # - File operations: Standard keys (y=yank/copy, d=cut, p=paste, x=trash)
      # - Top/Bottom: gg=go to top, gG=go to bottom
      # - Search: /=find, ?=find reverse, k=find next, K=find previous
      # - Create/Rename: c=create file, r=rename file
      # - Sort: s prefixed keys (sn=natural, ss=size, sm=time, se=extension)
      # - Advanced: ~=help, H=toggle hidden files, Z=fuzzy find with fzf
      # - Theme: Custom Rose Pine Moon theme for a cohesive visual experience
      keymap = {
        # Main file manager keybindings
        mgr = {
          keymap = [
            # Unbind hjkl
            {
              on = "h";
              run = "noop";
              desc = "Unbound";
            }
            {
              on = "j";
              run = "noop";
              desc = "Unbound";
            }
            # {
            #   on = "k";  # k is actually replaced instead of unbound
            #   run = "noop";
            #   desc = "Unbound";
            # }
            {
              on = "l";
              run = "noop";
              desc = "Unbound";
            }

            # Colemak MNEI navigation
            {
              on = "n";
              run = "arrow 1";
              desc = "Move cursor down (Colemak)";
            }
            {
              on = "e";
              run = "arrow -1";
              desc = "Move cursor up (Colemak)";
            }
            {
              on = "m";
              run = "leave";
              desc = "Go back to parent directory (Colemak)";
            }
            {
              on = "i";
              run = "enter";
              desc = "Enter directory (Colemak)";
            }

            # Jump to top/bottom of file list with numeric values
            # Two-key approach with g prefix for consistency
            {
              on = ["g" "g"]; # Two g keys in sequence for top
              run = "arrow -9999"; # Very negative number to go to top
              desc = "Go to the top of file list (gg)";
            }
            {
              on = ["g" "G"]; # g followed by G for bottom
              run = "arrow 9999"; # Very positive number to go to bottom
              desc = "Go to the bottom of file list (gG)";
            }

            # Arrow keys as fallback navigation
            {
              on = "<Up>";
              run = "arrow -1";
              desc = "Move cursor up";
            }
            {
              on = "<Down>";
              run = "arrow 1";
              desc = "Move cursor down";
            }
            {
              on = "<Left>";
              run = "leave";
              desc = "Go back to parent directory";
            }
            {
              on = "<Right>";
              run = "enter";
              desc = "Enter directory";
            }

            # Quit/Cancel
            {
              on = "q";
              run = "quit";
              desc = "Quit";
            }
            {
              on = "<Esc>";
              run = "escape";
              desc = "Cancel or clear";
            }

            # Basic operations
            {
              on = "<Enter>";
              run = "open";
              desc = "Open file";
            }
            {
              on = "<Space>";
              run = ["toggle" "arrow 1"];
              desc = "Select and move down";
            }

            # File operations
            # Note: Yazi resolves keybinding conflicts by using the first matching key
            # For example, "y" works as a prefix for ["y" "p"] sequences and also as a standalone key
            # So pressing "y" then waiting executes the "yank" command, while pressing "yp" quickly executes "copy path"
            {
              on = "y";
              run = "yank";
              desc = "Yank/copy selected files";
            }
            {
              on = "d";
              run = "yank --cut";
              desc = "Cut selected files";
            }
            {
              on = "p";
              run = "paste";
              desc = "Paste files";
            }
            {
              on = "P";
              run = "paste --force";
              desc = "Paste files (overwrite)";
            }
            {
              on = "x";
              run = "remove";
              desc = "Move to trash";
            }
            {
              on = "X";
              run = "remove --permanently";
              desc = "Delete permanently";
            }

            # Selection operations
            {
              on = "a";
              run = "toggle_all";
              desc = "Toggle selection of all files";
            }
            {
              on = "u"; # Added a way to unmark a single file
              run = "toggle --state=off";
              desc = "Unselect the current file";
            }
            {
              on = "v";
              run = "visual_mode";
              desc = "Enter visual selection mode";
            }
            {
              on = "V";
              run = "visual_mode --unset";
              desc = "Enter visual deselection mode";
            }

            {
              on = "f";
              run = "filter --smart";
              desc = "Filter files";
            }
            {
              on = "H"; # Changed from "h" to "H" to avoid conflict with the intentionally unbound "h" key
              run = "hidden toggle";
              desc = "Toggle hidden files";
            }

            # Sort commands - using "s" as a prefix
            # Note: The sort commands use key sequences that require pressing keys in sequence
            # For example, "s" then "n" for natural sort
            {
              on = ["s" "n"];
              run = "sort natural --reverse=no";
              desc = "Sort naturally";
            }
            {
              on = ["s" "N"];
              run = "sort natural --reverse";
              desc = "Sort naturally (reverse)";
            }
            {
              on = ["s" "s"];
              run = ["sort size --reverse=no" "linemode size"];
              desc = "Sort by size";
            }
            {
              on = ["s" "S"];
              run = ["sort size --reverse" "linemode size"];
              desc = "Sort by size (reverse)";
            }
            {
              on = ["s" "m"];
              run = ["sort mtime --reverse=no" "linemode mtime"];
              desc = "Sort by modified time";
            }
            {
              on = ["s" "M"];
              run = ["sort mtime --reverse" "linemode mtime"];
              desc = "Sort by modified time (reverse)";
            }
            {
              on = ["s" "e"];
              run = "sort extension --reverse=no";
              desc = "Sort by extension";
            }
            {
              on = ["s" "E"];
              run = "sort extension --reverse";
              desc = "Sort by extension (reverse)";
            }

            # Search (use / as in vim)
            {
              on = "/";
              run = "find --smart";
              desc = "Find files";
            }
            {
              on = "?";
              run = "find --previous --smart";
              desc = "Find files (reverse)";
            }
            # Add explicit backspace binding for find mode
            # Find next/previous with k/K keys
            {
              on = "k";
              run = "find_arrow";
              desc = "Go to next match";
            }
            {
              on = "K";
              run = "find_arrow --previous";
              desc = "Go to previous match";
            }

            # Create/Rename
            # Using c for create since a doesn't work
            {
              on = "c";
              run = "create";
              desc = "Create file/directory";
            }
            {
              on = "r";
              run = "rename --cursor=before_ext";
              desc = "Rename file";
            }

            # Shell / External commands
            {
              on = ";";
              run = "shell --interactive";
              desc = "Run shell command";
            }
            {
              on = ":";
              run = "shell --block --interactive";
              desc = "Run blocking shell command";
            }

            # FZF integration for fuzzy finding
            {
              on = "Z";
              run = "plugin fzf";
              desc = "Fuzzy find files with FZF";
            }

            # Tab operations - simple, no mode needed
            {
              on = "<C-t>";
              run = "tab_create --current";
              desc = "New tab";
            }
            {
              on = "<C-n>";
              run = "tab_switch 1 --relative";
              desc = "Next tab";
            }
            {
              on = "<C-e>";
              run = "tab_switch -1 --relative";
              desc = "Previous tab";
            }
            {
              on = "<C-w>";
              run = "close";
              desc = "Close tab";
            }

            # Copy functions
            {
              on = ["y" "p"];
              run = "copy path";
              desc = "Copy file path";
            }
            {
              on = ["y" "d"];
              run = "copy dirname";
              desc = "Copy directory path";
            }
            {
              on = ["y" "f"];
              run = "copy filename";
              desc = "Copy filename";
            }
            {
              on = ["y" "n"];
              run = "copy name_without_ext";
              desc = "Copy name without extension";
            }

            # Help
            {
              on = "~"; # Changed to tilde key, which is a standard help key in Yazi
              run = "help";
              desc = "Show help";
            }
          ];
        };

        # Task manager mode - for managing copy/move/delete operations
        # Maintains the same Colemak navigation scheme
        tasks = {
          keymap = [
            # Unbind hjkl
            {
              on = "h";
              run = "noop";
              desc = "Unbound";
            }
            {
              on = "j";
              run = "noop";
              desc = "Unbound";
            }
            {
              on = "k";
              run = "noop";
              desc = "Unbound";
            }
            {
              on = "l";
              run = "noop";
              desc = "Unbound";
            }

            # Replace with Colemak bindings
            {
              on = "n";
              run = "arrow 1";
              desc = "Move cursor down";
            }
            {
              on = "e";
              run = "arrow -1";
              desc = "Move cursor up";
            }

            # Other controls remain the same
            {
              on = "<Esc>";
              run = "close";
              desc = "Close task manager";
            }
            {
              on = "<C-c>";
              run = "close";
              desc = "Close task manager";
            }
            {
              on = "w";
              run = "close";
              desc = "Close task manager";
            }
            {
              on = "<Enter>";
              run = "inspect";
              desc = "Inspect the task";
            }
            {
              on = "x";
              run = "cancel";
              desc = "Cancel the task";
            }
          ];
        };

        # Input mode - used during file name entry, search, etc.
        # Includes Colemak-friendly cursor movement and explicit backspace binding
        input = {
          keymap = [
            # Remove hjkl bindings and replace with Colemak equivalents
            {
              on = "h";
              run = "noop";
              desc = "Unbound";
            }
            {
              on = "j";
              run = "noop";
              desc = "Unbound";
            }
            {
              on = "k";
              run = "noop";
              desc = "Unbound";
            }
            {
              on = "l";
              run = "noop";
              desc = "Unbound";
            }

            # Colemak navigation in input mode
            {
              on = "m";
              run = "move -1";
              desc = "Move cursor back (Colemak)";
            }
            {
              on = "i";
              run = "move 1";
              desc = "Move cursor forward (Colemak)";
            }

            # Add explicit backspace binding for input (like find mode)
            {
              on = "<Backspace>";
              run = "backspace";
              desc = "Delete character before cursor";
            }
            {
              on = "<Delete>";
              run = "backspace --under";
              desc = "Delete character under cursor";
            }

            # Keep other standard inputs
            {
              on = "<C-c>";
              run = "close";
              desc = "Cancel input";
            }
            {
              on = "<Enter>";
              run = "close --submit";
              desc = "Submit input";
            }
            {
              on = "<Esc>";
              run = "escape";
              desc = "Go back to normal mode, or cancel input";
            }
          ];
        };
      };

      # Custom theme using Rose Pine Moon colors
      theme = builtins.fromTOML (builtins.readFile ./yazi-theme/rose-pine-moon.toml);
    };
    home.packages = with pkgs;
      if isLinux
      then [
        imv
        mpv
      ]
      else [];
  };
}
