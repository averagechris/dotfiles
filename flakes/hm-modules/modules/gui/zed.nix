{...}: {
  programs.zed-editor = {
    # list of extension names
    extensions = [
      "Nix"
      "Python LSP"
      "Ruff"
    ];
    userSettings = {
      theme = "Rosé Pine Moon";

      base_keymap = "VSCode";
      vim_mode = true;
      ui_font_size = 16;
      buffer_font_size = 16;
      autosave = "off";
      autoupdate = true;
      confirm_quit = true;
      load_direnv = "shell_hook";
      cursor_blink = false;
      git = {
        inline_blame = {
          enabled = false;
        };
      };
      indent_guides = {
        enabled = false;
        coloring = "indent_aware";
        background_coloring = "disabled";
      };
      inlay_hints = {
        enabled = false;
        show_type_hints = true;
        show_parameter_hints = true;
        show_other_hints = true;
        show_background = false;
        edit_debounce_ms = 700;
        scroll_debounce_ms = 50;
      };
      metric = false;
      preview_tabs = {
        enabled = true;
        enable_preview_from_file_finder = true;
        enable_preview_from_code_navigation = true;
      };
      show_whitespaces = "selection";
      telemetry = {
        diagnostics = false;
        metrics = false;
      };
      terminal = {
        alternate_scroll = "off";
        blinking = "terminal_controlled";
        copy_on_select = true;
        dock = "bottom";
        detect_venv = {
          on = {
            directories = [".venv" "venv"];
            activate_script = "default";
          };
        };
        env = {
          ZED = "1";
        };
        font_family = null;
        font_features = null;
        font_size = null;
        line_height = "comfortable";
        option_as_meta = false;
        button = false;
        # shell = {};
        toolbar = {
          breadcrumbs = true;
        };
        working_directory = "current_project_directory";
        vim_mode = false;
      };
      vim = {
        use_multiline_find = true;
        use_smartcase_find = true;
        languages.Python = {
          language_servers = ["ruff"];
          format_on_save = "on";
          formatter = [
            {
              code_actions = {
                # // Fix all auto-fixable lint violations
                "source.fixAll.ruff" = true;
                # // Organize imports
                "source.organizeImports.ruff" = true;
              };
            }
          ];
        };
      };
    };
    userKeymaps = [
      {
        "context" = "Editor && (showing_code_actions || showing_completions)";
        "bindings" = {
          "ctrl-n" = "editor::ContextMenuNext";
          "ctrl-e" = "editor::ContextMenuPrev";
        };
      }
      {
        context = "Editor && VimControl && !VimWaiting && !menu";
        bindings = {
          # Motion
          ctrl-shift-alt-w = "vim::NextWordStart";
          ctrl-shift-alt-b = "vim::PreviousWordStart";
          ctrl-shift-alt-e = "vim::NextWordEnd";
          # Goto mode
          "g n" = "pane::ActivateNextItem";
          "g p" = "pane::ActivatePrevItem";
          # "tab" = "pane::ActivateNextItem";
          # "shift-tab"= "pane::ActivatePrevItem";
          E = "pane::ActivatePrevItem";
          N = "pane::ActivateNextItem";
          "g i" = "vim::EndOfLine";
          "g m" = "vim::StartOfLine";
          "g s" = "vim::FirstNonWhitespace"; # "g s" default behavior is "space s"
          "g G" = "vim::EndOfDocument";
          "g y" = "editor::GoToTypeDefinition";
          "g r" = "editor::FindAllReferences"; # zed specific
          "g t" = "vim::WindowTop";
          "g c" = "vim::WindowMiddle";
          "g b" = "vim::WindowBottom";
          # Window mode
          "space w m" = ["workspace::ActivatePaneInDirection" "Left"];
          "space w i" = ["workspace::ActivatePaneInDirection" "Right"];
          "space w e" = ["workspace::ActivatePaneInDirection" "Up"];
          "space w n" = ["workspace::ActivatePaneInDirection" "Down"];
          "space w q" = "pane::CloseActiveItem";
          "space w d" = "pane::CloseActiveItem";
          "space w v" = "pane::SplitRight";
          "space w h" = "pane::SplitDown";
          # Space mode
          "space f f" = "file_finder::Toggle";
          "space k" = "editor::Hover";
          "space l o" = "outline::Toggle";
          "space shift-s" = "project_symbols::Toggle";
          "space d" = "editor::GoToDiagnostic";
          "space shift-d" = "diagnostics::Deploy";
          "space r" = "editor::Rename";
          "space l a" = "editor::ToggleCodeActions";
          "space l i" = "editor::ToggleInlayHints";
          "space h" = "editor::SelectAllMatches";
          "space t i" = "editor::ToggleIndentGuides";
          "space t n" = "editor::ToggleLineNumbers";
          "space t r" = "editor::ToggleRelativeLineNumbers";
          "space t g b" = "editor::ToggleGitBlameInline";
          "space t w" = "editor::ToggleSoftWrap";
          "space o p" = "workspace::ToggleLeftDock";
          "space o a" = "workspace::ToggleRightDock";
          "space o t" = "workspace::ToggleBottomDock";
          # Match mode
          "h h" = "vim::Matching";
          "h i w" = ["workspace::SendKeystrokes" "v i w"];
          # Misc
          "ctrl-e" = "editor::MoveLineUp";
          "ctrl-n" = "editor::MoveLineDown";
          #  n = "vim::PreviousWordStart";
          "ctrl-v" = "editor::Paste";
          "shift-u" = "editor::Redo";
          d = "vim::DeleteRight";
          "space s a" = "editor::SelectAll";
          "space t c" = "editor::ToggleComments";
          "space b s" = "workspace::Save";
        };
      }
      {
        context = "Editor && VimControl && (vim_mode == normal || vim_mode == visual) && !VimWaiting && !menu";
        bindings = {
          # // put key-bindings here if you want them to work in normal & visual mode
          j = "null";
          k = "null";
          h = "null";
          # l = "null";
          m = "vim::Left";
          n = "vim::Down";
          e = "vim::Up";
          i = "vim::Right";
          l = "vim::InsertBefore";
          a = "vim::InsertAfter";
        };
      }
      {
        "context" = "Editor && VimControl && vim_mode == normal && !VimWaiting && !menu";
        "bindings" = {
          # put key-bindings here if you want them to work only in normal mode
          "b" = ["workspace::SendKeystrokes" "v ctrl-shift-alt-b"];
          "w" = ["workspace::SendKeystrokes" "v ctrl-shift-alt-e"];
          "x" = "vim::ToggleVisualLine";
        };
      }
      {
        "context" = "Editor && VimControl && vim_mode == visual && !VimWaiting && !menu";
        "bindings" = {
          # visual visual line & visual block modes
          "b" = ["workspace::SendKeystrokes" "v v ctrl-shift-alt-b"];
          "w" = ["workspace::SendKeystrokes" "v v ctrl-shift-alt-e"];
          "x" = ["workspace::SendKeystrokes" "j"];
        };
      }
      {
        "context" = "Editor && VimControl && vim_mode == insert && !menu";
        "bindings" = {
          # put key-bindings here if you want them to work in insert mode
        };
      }
      {
        "context" = "Dock";
        "bindings" = {
          # Window mode
          "ctrl-w m" = ["workspace::ActivatePaneInDirection" "Left"];
          "ctrl-w i" = ["workspace::ActivatePaneInDirection" "Right"];
          "ctrl-w n" = ["workspace::ActivatePaneInDirection" "Up"];
          "ctrl-w e" = ["workspace::ActivatePaneInDirection" "Down"];
        };
      }
      {
        "context" = "Picker || menu";
        "bindings" = {
          "ctrl-n" = "menu::SelectNext";
          "ctrl-e" = "menu::SelectPrev";
          "ctrl-p" = "None";
        };
      }
    ];
  };
}
