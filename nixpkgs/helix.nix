{
  inputs,
  system,
  ...
}: {
  programs.helix = {
    package = inputs.helix.packages.${system}.default;
    settings = {
      theme = "rose_pine_moon";
      editor = {
        auto-save = {
          focus-lost = true;
          after-delay.enable = true;
          after-delay.timeout = 20000;
        };
        completion-replace = false;
        cursor-shape = {
          normal = "block";
          insert = "bar";
          select = "block";
        };
        file-picker = {
          hidden = false;
          follow-symlinks = true;
          deduplicate-links = true;
          parents = true;
          ignore = true;
          git-ignore = true;
          git-global = true;
          git-exclude = true;
        };
        gutters = ["diagnostics" "diff"];
        indent-guides = {
          character = "┊";
          skip-levels = 1;
        };
        line-number = "relative";
        lsp = {
          enable = true;
          auto-signature-help = true;
          display-messages = false;
          display-signature-help-docs = true;
          goto-reference-include-declaration = true;
        };
        smart-tab = {
          enable = true;
          supersede-menu = true;
        };
      };

      keys.select = {
        h = "no_op";
        j = "no_op";
        k = "search_next";
        l = "insert_mode";
        m = "extend_char_left";
        n = "extend_visual_line_down";
        e = "extend_visual_line_up";
        i = "extend_char_right";
        K = "search_prev";
        g.m = "goto_line_start";
        g.h = "no_op";
        g.i = "goto_line_end";
        g.l = "no_op";
        g.j = "no_op";
        g.k = "no_op";
        g.G = "goto_last_line";
      };
      keys.normal = {
        # cursor/selection movement and manipulation
        m = "move_char_left";
        n = "move_visual_line_down";
        e = "move_visual_line_up";
        i = "move_char_right";
        w = "move_next_word_start";
        W = "move_next_long_word_start";
        b = "move_prev_word_start";
        B = "move_prev_long_word_start";
        E = "move_next_word_end";
        f = "find_till_char";
        F = "find_prev_char";
        "C-." = "repeat_last_motion";
        esc = ["collapse_selection" "keep_primary_selection"];
        C = "copy_selection_on_next_line";
        C-S-c = "copy_selection_on_prev_line";
        s = "select_regex";
        S = "split_selection_on_newline";
        x = "extend_line_below";
        X = "extend_to_line_bounds";
        "(" = "rotate_selection_contents_forward";
        ")" = "rotate_selection_contents_backward";
        "J" = "join_selections";
        "C-S-j" = "join_selections_space";
        C-n = "select_next_sibling";
        C-e = "select_prev_sibling";
        C-S-e = "expand_selection";
        C-S-n = "shrink_selection";
        k = "search_next";
        K = "search_prev";
        ":" = "command_mode";

        # changes
        a = "append_mode";
        A = "insert_at_line_end";
        c = "change_selection";
        d = "delete_selection";
        l = "insert_mode";
        L = "insert_at_line_start";
        o = "open_below";
        O = "open_above";
        p = "paste_after";
        P = "paste_before";
        r = "replace";
        R = "replace_with_yanked";
        u = "undo";
        U = "redo";
        y = "yank";
        "~" = "switch_case";
        ">" = "indent";
        "<" = "unindent";

        # incr/decr selected text obj
        A-e = "increment";
        A-n = "decrement";

        # macros
        q = "record_macro";
        Q = "replay_macro";

        # sending selected contents to shell
        "|" = "shell_pipe"; # replaces selection with shell output
        "C-|" = "shell_pipe_to"; # ignores shell output
        "!" = "shell_insert_output"; # prepends shell output
        "C-!" = "shell_append_output"; # appends shell output
        "$" = "shell_keep_pipe"; # filters selections, keeps any where shell returns status of 0

        "N" = "no_op";
        "%" = "no_op";
        A-c = "no_op";
        A-d = "no_op";
        A-u = "no_op";
        A-U = "no_op";
        C-s = "no_op";
        "`" = "no_op";
        "A-|" = "no_op";
        "A-`" = "no_op";
        end = "no_op";
        home = "no_op";
        pageup = "no_op";
        pagedown = "no_op";
        G = "no_op";
        C-b = "no_op";
        A-C = "no_op";
        C-u = "no_op";
        C-d = "no_op";
        A-x = "no_op";
        A-s = "no_op";
        "A-." = "no_op";
        "A-;" = "no_op";
        "_" = "no_op";
        "A-:" = "no_op";
        ";" = "no_op";
        "A-," = "no_op";
        "A-_" = "no_op";
        A-minus = "no_op";
        "A-(" = "no_op";
        "A-)" = "no_op";
        A-S-j = "no_op";
        A-o = "no_op";
        A-up = "no_op";
        A-i = "no_op";
        A-down = "no_op";
        A-p = "no_op";
        A-left = "no_op";
        A-right = "no_op";
        "&" = "no_op";
        j = "no_op";
        I = "no_op";
        "=" = "no_op";
        C-c = "no_op";
        C-a = "no_op";
        space.S = "no_op"; # lsp workspace sympol picker
        space.d = "no_op"; # lsp diagnostic picker
        space.D = "no_op"; # lsp workspace diagnostic picker
        space.r = "no_op"; # lsp rename
        space.k = "no_op"; # lsp show docs

        # goto mode
        g.g = "goto_file_start";
        g.G = "goto_last_line";
        g.m = "goto_line_start";
        g.i = "goto_line_end";
        g.e = "move_line_up";
        g.n = "move_line_down";
        g.E = "goto_window_top";
        g.N = "goto_window_bottom";
        g."." = "goto_last_modification";
        g.w = "goto_word";
        # these gotos use the lsp
        g.d = "goto_definition";
        g.D = "goto_type_definition";
        g.r = "goto_reference";
        g.a = "no_op";
        g.b = "no_op";
        g.c = "no_op";
        g.f = "no_op";
        g.h = "no_op";
        g.j = "no_op";
        g.k = "no_op";
        g.l = "no_op";
        g.p = "no_op";
        g.s = "no_op";
        g.t = "no_op";

        # match mode
        h.h = "match_brackets";
        h.s = "surround_add";
        h.r = "surround_replace";
        h.d = "surround_delete";
        h.a = "select_textobject_around";
        h.i = "select_textobject_inner";

        # view mode
        z.n = "scroll_down";
        z.e = "scroll_up";
        Z.n = "scroll_down";
        Z.e = "scroll_up";
        z.k = "search_next";
        z.K = "search_prev";
        Z.k = "search_next";
        Z.K = "search_prev";
        z.N = "no_op";
        Z.N = "no_op";

        # text "actions" minor mode
        space.a = {
          s = ":sort";
          S = ":rsort";
          c = "toggle_comments";
          C = "align_selections"; # aligns text in columns
          l = "switch_to_lowercase";
          u = "switch_to_uppercase";
        };

        # "buffer" minor mode
        space.b = {
          b = "buffer_picker";
          d = ":buffer-close";
          D = ":buffer-close!";
          f = "file_picker_in_current_buffer_directory";
          F = ":format";
          j = ":buffer-next";
          k = ":buffer-previous";
          n = ":buffer-next";
          p = ":buffer-previous";
          N = ":new"; # open new "scratch" buffer
          V = ":vsplit-new"; # open new "scratch" buffer in a vsplit
          S = ":hsplit-new"; # open new "scratch" buffer in a horizontal split
          w = ":write";
          W = ":write!";
        };

        # "file" minor mode
        space.f = {
          f = "file_picker";
          s = ":write";
          S = ":write!";
        };

        # "go" minor mode
        space.g = {
          # for muscle memory of the gitui binding
          g = ":sh zellij run --direction up --close-on-exit --name gitui -- gitui && zellij action toggle-fullscreen";
        };

        # "git" minor mode
        space.G = {
          g = ":sh zellij run --direction up --close-on-exit --name gitui -- gitui && zellij action toggle-fullscreen";
          # s currenty reserved for the lsp debugger stuff TODO fix it
          S = ":sh git add .";
          p = ":sh zellij run --floating --name pre-commit -- pre-commit";
        };

        # "jumplist" minor mode
        space.j = {
          j = "jumplist_picker";
          e = "jump_forward"; # traverse jumplist stack
          n = "jump_backward"; # traverse jumplist stack
          s = "save_selection"; # saves selected point to jumplist
        };

        # "language" server minor mode
        space.l = {
          a = "code_action";
          d = "diagnostics_picker";
          D = "workspace_diagnostics_picker";
          k = "hover";
          r = "rename_symbol";
          s = "symbol_picker";
          S = "workspace_symbol_picker";
          f = ":format";
          F = "format_selections";
        };

        # "selections" minor mode for advanced selection stuff
        space.s = {
          a = "select_all";
          e = "extend_next_word_end";
          E = "extend_next_long_word_end";
          f = "flip_selections";
          F = "ensure_selections_forward";
          k = "keep_primary_selection";
          K = "remove_primary_selection";
          m = "merge_consecutive_selections";
          M = "merge_selections";
          r = "keep_selections"; # exclude selections that dont match a regex
          R = "remove_selections"; # exclude selections that do match a regex
          s = "split_selection";
          x = "shrink_to_line_bounds";
          ">" = "rotate_selections_forward";
          "<" = "rotate_selections_backward";
          "," = "collapse_selection";
          space = "trim_selections";
        };

        # "toggle" minor mode
        space.t = {
          c = "toggle_comments";
          w = ":toggle-option soft-wrap.enable";
          h = ":toggle-option lsp.display-inlay-hints";

          # toggling non-booleans will be massively improved with: https://github.com/helix-editor/helix/pull/4411
          s = ":set-option whitespace.render all";
          S = ":set-option whitespace.render none";
          i = ":toggle-option indent-guides.render";
          N = '':set-option gutters ["diagnostics","diff"]'';
          n = '':set-option gutters ["diagnostics","diff","line-numbers"]'';
          T = ":theme rose_pine_moon";
          t = ":theme rose_pine_dawn";
        };

        # "quit" minor mode
        space.q = {
          w = ":write-quit";
          W = ":write-quit!";
          s = ":write-quit-all";
          S = ":write-quit-all!";
          q = ":quit";
          Q = ":quit!";
        };

        # minor-mode "window"
        space.w = {
          H = "no_op";
          J = "no_op";
          K = "no_op";
          L = "no_op";
          h = "no_op";
          j = "no_op";
          k = "no_op";
          l = "no_op";
          # bindings start here
          E = "swap_view_up";
          I = "swap_view_right";
          M = "swap_view_left";
          N = "swap_view_down";
          d = "wclose"; # space.w.q is the default binding
          e = "jump_view_up";
          i = "jump_view_right";
          m = "jump_view_left";
          n = "jump_view_down";
          p = ":sh zellij action toggle-floating-panes"; # pop the floating zellij panes if any
          s = ":hsplit";
          v = ":vsplit";
        };
      };
    };
    languages = {
      language-server.pylsp = {
        command = "pylsp";
        config = {
          pylsp.plugins = {
            rope_autoimport.enabled = true;
          };
        };
      };
      language-server.ruff = {
        command = "ruff";
        args = ["server" "--preview"];
      };
      language = [
        {
          # lsp: https://github.com/rust-lang/rust-analyzer
          name = "rust";
          auto-pairs = {
            "(" = ")";
            "{" = "}";
            "[" = "]";
            "\"" = "\"";
            "`" = "`";
            "<" = ">";
          };
        }
        {
          # lsp: https://github.com/oxalica/nil
          name = "nix";
          formatter = {
            command = "alejandra";
            args = ["-"];
          };
          # language-server = {
          #   command = "nixd";
          #   args = [];
          #   environment = {};
          # };
        }
        {
          # lsp: https://github.com/python-lsp/python-lsp-server
          name = "python";
          formatter = {
            command = "ruff";
            args = ["format" "--quiet" "-"];
          };
          language-servers = ["pylsp" "ruff"];
        }
        # {
        #   # lsp: https://github.com/bash-lsp/bash-language-server
        #   name = "bash";
        # }
        # {
        #   name = "toml";
        # }
      ];
    };
  };
}
