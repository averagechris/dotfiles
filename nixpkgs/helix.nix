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
        space.":" = "command_mode";

        # minor-mode "buffer"
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
        };

        # minor-mode "file"
        space.f = {
          f = "file_picker";
          s = ":write";
          S = ":write!";
        };

        # minor-mode "git"
        space.g = {
          g = ":sh zellij run --direction up --close-on-exit --name gitui -- gitui && zellij action toggle-fullscreen";
          # s currenty reserved for the lsp debugger stuff TODO fix it
          S = ":sh git add .";
          p = ":sh zellij run --floating --name pre-commit -- pre-commit";
        };

        # minor-mode "toggle"
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

        # minor-mode "window"
        space.w = {
          d = "wclose"; # space.w.q is the default binding
          v = ":vsplit";
          s = ":hsplit";
          # pop the floating zellij panes if any
          p = ":sh zellij action toggle-floating-panes";
        };

        space.q.q = ":quit";
        space.q.Q = ":quit!";
        esc = ["collapse_selection" "keep_primary_selection"];

        # default unbinds
        "C-c" = "no_op"; # was: toggle_comments

        # colemak related changes
        m = "move_char_left";
        n = "move_line_down";
        e = "move_line_up";
        i = "move_char_right";
        j = "no_op";

        g.m = "goto_line_start";
        g.h = "no_op";
        g.i = "goto_line_end";
        g.l = "no_op";
        g.j = "no_op";
        g.k = "no_op";
        g.G = "goto_last_line";

        h.h = "match_brackets";
        h.s = "surround_add";
        h.r = "surround_replace";
        h.d = "surround_delete";
        h.a = "select_textobject_around";
        h.i = "select_textobject_inner";

        space.w.h = "no_op";
        space.w.H = "no_op";
        space.w.j = "no_op";
        space.w.J = "no_op";
        space.w.k = "no_op";
        space.w.K = "no_op";
        space.w.l = "no_op";
        space.w.L = "no_op";
        space.w.m = "jump_view_left";
        space.w.n = "jump_view_down";
        space.w.e = "jump_view_up";
        space.w.i = "jump_view_right";
        space.w.M = "swap_view_left";
        space.w.N = "swap_view_down";
        space.w.E = "swap_view_up";
        space.w.I = "swap_view_right";

        z.n = "scroll_down";
        z.e = "scroll_up";
        Z.n = "scroll_down";
        Z.e = "scroll_up";

        l = "insert_mode";
        L = "insert_at_line_start";

        I = "no_op";
        N = "keep_selections";
        E = "join_selections";

        k = "search_next";
        K = "search_prev";
        f = "move_next_word_end";
        F = "move_next_long_word_end";
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
