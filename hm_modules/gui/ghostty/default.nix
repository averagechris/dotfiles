{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.ghostty;
in {
  options.dotfiles.ghostty = {
    enable = lib.mkEnableOption "Ghostty terminal emulator configuration";
  };

  config = lib.mkIf cfg.enable (let
    # Binding constructor
    mk = {
      trigger,
      action,
      desc,
      pretty ? null,
    }: {inherit trigger action desc pretty;};

    # Category definitions in your modal strategy (leader = Shift+Space)
    tabs = [
      (mk {
        trigger = "shift+space>t>n";
        action = "new_tab";
        desc = "new tab";
        pretty = "t n";
      })
      (mk {
        trigger = "shift+space>t>d";
        action = "close_tab";
        desc = "close tab";
        pretty = "t d";
      })
      (mk {
        trigger = "shift+space>t>t";
        action = "toggle_tab_overview";
        desc = "toggle tab overview";
        pretty = "t t";
      })
      (mk {
        trigger = "shift+space>t>r";
        action = "prompt_surface_title";
        desc = "set tab title (prompt)";
        pretty = "t r";
      })
      (mk {
        trigger = "shift+space>t>1";
        action = "goto_tab:1";
        desc = "goto tab 1";
        pretty = "t 1";
      })
      (mk {
        trigger = "shift+space>t>2";
        action = "goto_tab:2";
        desc = "goto tab 2";
        pretty = "t 2";
      })
      (mk {
        trigger = "shift+space>t>3";
        action = "goto_tab:3";
        desc = "goto tab 3";
        pretty = "t 3";
      })
      (mk {
        trigger = "shift+space>t>4";
        action = "goto_tab:4";
        desc = "goto tab 4";
        pretty = "t 4";
      })
      (mk {
        trigger = "shift+space>t>5";
        action = "goto_tab:5";
        desc = "goto tab 5";
        pretty = "t 5";
      })
      (mk {
        trigger = "shift+space>t>6";
        action = "goto_tab:6";
        desc = "goto tab 6";
        pretty = "t 6";
      })
      (mk {
        trigger = "shift+space>t>7";
        action = "goto_tab:7";
        desc = "goto tab 7";
        pretty = "t 7";
      })
      (mk {
        trigger = "shift+space>t>8";
        action = "goto_tab:8";
        desc = "goto tab 8";
        pretty = "t 8";
      })
      (mk {
        trigger = "shift+space>t>9";
        action = "goto_tab:9";
        desc = "goto tab 9";
        pretty = "t 9";
      })
      (mk {
        trigger = "shift+space>t>m";
        action = "previous_tab";
        desc = "previous tab";
        pretty = "t m";
      })
      (mk {
        trigger = "shift+space>t>i";
        action = "next_tab";
        desc = "next tab";
        pretty = "t i";
      })
      (mk {
        trigger = "shift+space>t>shift+m";
        action = "goto_tab:1";
        desc = "first tab";
        pretty = "t M";
      })
      (mk {
        trigger = "shift+space>t>shift+i";
        action = "last_tab";
        desc = "last tab";
        pretty = "t I";
      })
    ];

    windows = [
      (mk {
        trigger = "shift+space>w>d";
        action = "close_surface";
        desc = "close split (surface)";
        pretty = "w d";
      })
      (mk {
        trigger = "shift+space>w>f";
        action = "toggle_split_zoom";
        desc = "toggle split zoom";
        pretty = "w f";
      })
      # Navigate splits (m n e i = left/down/up/right)
      (mk {
        trigger = "shift+space>w>m";
        action = "goto_split:left";
        desc = "goto split left";
        pretty = "w m";
      })
      (mk {
        trigger = "shift+space>w>n";
        action = "goto_split:down";
        desc = "goto split down";
        pretty = "w n";
      })
      (mk {
        trigger = "shift+space>w>e";
        action = "goto_split:up";
        desc = "goto split up";
        pretty = "w e";
      })
      (mk {
        trigger = "shift+space>w>i";
        action = "goto_split:right";
        desc = "goto split right";
        pretty = "w i";
      })
      # Create splits
      (mk {
        trigger = "shift+space>w>s";
        action = "new_split:down";
        desc = "new split down (stacked)";
        pretty = "w s";
      })
      (mk {
        trigger = "shift+space>w>v";
        action = "new_split:right";
        desc = "new split right (vertical)";
        pretty = "w v";
      })
      # Resize
      (mk {
        trigger = "shift+space>w>r>m";
        action = "resize_split:left,1";
        desc = "resize split left";
        pretty = "w r m";
      })
      (mk {
        trigger = "shift+space>w>r>n";
        action = "resize_split:down,1";
        desc = "resize split down";
        pretty = "w r n";
      })
      (mk {
        trigger = "shift+space>w>r>e";
        action = "resize_split:up,1";
        desc = "resize split up";
        pretty = "w r e";
      })
      (mk {
        trigger = "shift+space>w>r>i";
        action = "resize_split:right,1";
        desc = "resize split right";
        pretty = "w r i";
      })
      # Resize chord shift+ctrl+?
      (mk {
        trigger = "shift+ctrl+m";
        action = "resize_split:left,5";
        desc = "resize split left";
        pretty = "w r m";
      })
      (mk {
        trigger = "shift+ctrl+n";
        action = "resize_split:down,5";
        desc = "resize split down";
        pretty = "w r n";
      })
      (mk {
        trigger = "shift+ctrl+e";
        action = "resize_split:up,5";
        desc = "resize split up";
        pretty = "w r e";
      })
      (mk {
        trigger = "shift+ctrl+i";
        action = "resize_split:right,5";
        desc = "resize split right";
        pretty = "w r i";
      })
      # Layout and window toggles
      (mk {
        trigger = "shift+space>w>l>r";
        action = "equalize_splits";
        desc = "equalize splits";
        pretty = "w l r";
      })
      (mk {
        trigger = "shift+space>w>0";
        action = "reset_window_size";
        desc = "reset window size";
        pretty = "w 0";
      })
      (mk {
        trigger = "shift+space>w>u";
        action = "toggle_maximize";
        desc = "toggle maximize";
        pretty = "w u";
      })
      (mk {
        trigger = "shift+space>w>y";
        action = "toggle_fullscreen";
        desc = "toggle fullscreen";
        pretty = "w y";
      })
      (mk {
        trigger = "shift+space>w>x";
        action = "toggle_window_decorations";
        desc = "toggle window decorations";
        pretty = "w x";
      })
      (mk {
        trigger = "shift+space>w>o";
        action = "toggle_window_float_on_top";
        desc = "toggle float on top";
        pretty = "w o";
      })
      (mk {
        trigger = "shift+space>w>g";
        action = "show_gtk_inspector";
        desc = "GTK inspector";
        pretty = "w g";
      })
      (mk {
        trigger = "shift+space>w>k";
        action = "show_on_screen_keyboard";
        desc = "on-screen keyboard";
        pretty = "w k";
      })
      (mk {
        trigger = "shift+space>w>h";
        action = "toggle_visibility";
        desc = "toggle visibility";
        pretty = "w h";
      })
    ];

    font = [
      (mk {
        trigger = "shift+ctrl+=";
        action = "increase_font_size:1";
        desc = "increase font size";
        pretty = "shift+ctrl+=";
      })
      (mk {
        trigger = "shift+ctrl+-";
        action = "decrease_font_size:1";
        desc = "decrease font size";
        pretty = "shift+ctrl+-";
      })
      (mk {
        trigger = "shift+ctrl+0";
        action = "reset_font_size";
        desc = "reset font size";
        pretty = "shift+ctrl+0";
      })
      (mk {
        trigger = "shift+space>f>r";
        action = "reset_font_size";
        desc = "reset font size";
        pretty = "f r";
      })
      (mk {
        trigger = "shift+space>f>1";
        action = "set_font_size:11.0";
        desc = "set font size 11";
        pretty = "f 1";
      })
      (mk {
        trigger = "shift+space>f>2";
        action = "set_font_size:12.0";
        desc = "set font size 12";
        pretty = "f 2";
      })
      (mk {
        trigger = "shift+space>f>3";
        action = "set_font_size:13.0";
        desc = "set font size 13";
        pretty = "f 3";
      })
    ];

    scroll = [
      (mk {
        trigger = "shift+space>s>e";
        action = "scroll_page_up";
        desc = "page up";
        pretty = "s e";
      })
      (mk {
        trigger = "shift+space>s>n";
        action = "scroll_page_down";
        desc = "page down";
        pretty = "s n";
      })
      (mk {
        trigger = "shift+space>s>i";
        action = "scroll_to_top";
        desc = "to top";
        pretty = "s i";
      })
      (mk {
        trigger = "shift+space>s>m";
        action = "scroll_to_bottom";
        desc = "to bottom";
        pretty = "s m";
      })
      (mk {
        trigger = "shift+space>s>g";
        action = "scroll_to_selection";
        desc = "to selection";
        pretty = "s g";
      })
    ];

    clipboard = [
      # Leader clipboard
      (mk {
        trigger = "shift+space>c";
        action = "copy_to_clipboard";
        desc = "copy to clipboard";
        pretty = "c";
      })
      (mk {
        trigger = "shift+space>v";
        action = "paste_from_clipboard";
        desc = "paste from clipboard";
        pretty = "v";
      })
      (mk {
        trigger = "shift+space>c>a";
        action = "select_all";
        desc = "select all";
        pretty = "c a";
      })
      (mk {
        trigger = "shift+space>c>u";
        action = "copy_url_to_clipboard";
        desc = "copy URL to clipboard";
        pretty = "c u";
      })
      (mk {
        trigger = "shift+space>c>t";
        action = "copy_title_to_clipboard";
        desc = "copy title to clipboard";
        pretty = "c t";
      })
      (mk {
        trigger = "shift+space>c>s";
        action = "paste_from_selection";
        desc = "paste from selection";
        pretty = "c s";
      })
      # Global clipboard fallbacks
      (mk {
        trigger = "ctrl+shift+c";
        action = "copy_to_clipboard";
        desc = "copy to clipboard";
        pretty = "Ctrl+Shift+C";
      })
      (mk {
        trigger = "ctrl+shift+v";
        action = "paste_from_clipboard";
        desc = "paste from clipboard";
        pretty = "Ctrl+Shift+V";
      })
    ];

    promptPalette = [
      (mk {
        trigger = "shift+space>p";
        action = "toggle_command_palette";
        desc = "command palette";
        pretty = "p";
      })
    ];

    configUtil = [
      (mk {
        trigger = "shift+space>l>o";
        action = "open_config";
        desc = "open config";
        pretty = "l o";
      })
      (mk {
        trigger = "shift+space>i>s";
        action = "toggle_secure_input";
        desc = "toggle secure input";
        pretty = "i s";
      })
    ];

    cheatsheetCat = [
      (mk {
        trigger = "shift+space>h>s";
        action = "new_split:down";
        desc = "open split (optional)";
        pretty = "h s";
      })
    ];

    categories = [
      {
        name = "Tabs (t)";
        list = tabs;
      }
      {
        name = "Windows/Splits (w)";
        list = windows;
      }
      {
        name = "Font (f)";
        list = font;
      }
      {
        name = "Scroll (s)";
        list = scroll;
      }
      {
        name = "Clipboard (c)";
        list = clipboard;
      }
      {
        name = "Prompt/Palette";
        list = promptPalette;
      }
      {
        name = "Config/Util";
        list = configUtil;
      }
      {
        name = "Cheatsheet";
        list = cheatsheetCat;
      }
    ];

    # Ghostty doesn't support multi-command sequences in a single text: action.
    # To avoid InvalidFormat, ensure action is a single action token.
    # For inline cheatsheet, we only clear with ESC c; showing text is done by shell commands, not supported by keybind.
    keybindStrings = builtins.concatLists (
      builtins.map (cat: builtins.map (b: "${b.trigger}=${b.action}") cat.list) categories
    );

    # Formatting helpers for the cheatsheet
    makePretty = b:
      if b.pretty != null
      then b.pretty
      else builtins.replaceStrings ["shift+space>" ">"] ["" " "] b.trigger;
    formatLine = b: "- `${makePretty b}` — ${b.desc}";
    formatCategory = cat: "## " + cat.name + "\n" + (builtins.concatStringsSep "\n" (builtins.map formatLine cat.list));

    cheatsheetText = ''
      # Ghostty Modal Keybindings

      Leader: `Shift+Space`

      ${builtins.concatStringsSep "\n\n" (builtins.map formatCategory categories)}
    '';
  in {
    programs.ghostty = {
      enable = true;
      # Start from a clean slate like kitty's clear_all_shortcuts
      clearDefaultKeybinds = true;

      # Follow shell program enables by default (users can override)
      enableZshIntegration = lib.mkDefault (config.programs.zsh.enable or false);
      enableBashIntegration = lib.mkDefault (config.programs.bash.enable or false);
      enableFishIntegration = lib.mkDefault (config.programs.fish.enable or false);

      settings = {
        # Behavior
        "window-inherit-working-directory" = true;
        "shell-integration" = "detect";

        # Visuals: Rose Pine Moon-inspired
        background = "#232136";
        foreground = "#e0def4";
        "selection-background" = "#44415a";
        "selection-foreground" = "#e0def4";

        # Keybindings generated from structured data above
        keybind = keybindStrings;

        # 16-color palette
        palette = [
          "0=#393552"
          "1=#eb6f92"
          "2=#9ccfd8"
          "3=#f6c177"
          "4=#3e8fb0"
          "5=#c4a7e7"
          "6=#ea9a97"
          "7=#e0def4"
          "8=#6e6a86"
          "9=#eb6f92"
          "10=#9ccfd8"
          "11=#f6c177"
          "12=#3e8fb0"
          "13=#c4a7e7"
          "14=#ea9a97"
          "15=#e0def4"
        ];
      };

      # Optional: install syntax for editors
      installVimSyntax = lib.mkDefault (config.programs.vim.enable or false);
      installBatSyntax = lib.mkDefault (pkgs ? bat);
    };

    # Deploy a readable cheatsheet generated from the bindings
    xdg.configFile = {
      "ghostty/cheatsheet.md".text = cheatsheetText;
    };
  });
}
