{...}: {
  programs.helix = {
    settings = {
      theme = "rose_pine_moon";
      editor = {
        auto-save = true;
        completion-replace = true;
        completion-trigger-len = 1;
        gutters = ["diagnostics" "diff"];
        line-number = "relative";
        lsp.display-messages = true;
        cursor-shape = {
          normal = "block";
          insert = "bar";
          select = "block";
        };
        indent-guides = {
          character = "┊";
          skip-levels = 1;
        };
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
      };
    };
    languages = {
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
            args = [];
          };
        }
        {
          # lsp: https://github.com/python-lsp/python-lsp-server
          name = "python";
          formatter = {
            command = "black";
            args = [];
          };
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
