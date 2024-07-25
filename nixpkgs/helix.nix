{
  config,
  inputs,
  lib,
  pkgs,
  system,
  ...
}: let
  gutters = ["diagnostics" "spacer" "diff"];
  statusline.center = [];
  launch_gitui_overlay = ":sh kitten @ launch --type=overlay --cwd=current gitui";
  just = cmd: ":sh ${pkgs.just}/bin/just --justfile .chris.just ${cmd} || true";
in {
  programs.helix = {
    package = inputs.helix.packages.${system}.default;
    settings = {
      theme = "rose_pine_moon";
      editor = {
        inherit gutters statusline;
        auto-completion = true;
        auto-format = true;
        bufferline = "never";
        completion-replace = false;
        cursorcolumn = false;
        cursorline = false;
        line-number = "relative";
        middle-click-paste = true;
        mouse = true;
        popup-border = "none";
        scroll-lines = 3;
        scrolloff = 2;
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
        indent-guides = {
          character = "┊";
          skip-levels = 1;
        };
        lsp = {
          enable = true;
          auto-signature-help = true;
          display-messages = false;
          display-inlay-hints = false;
          display-signature-help-docs = true;
          goto-reference-include-declaration = true;
          snippets = true;
        };
        smart-tab = {
          enable = true;
          supersede-menu = false;
        };
      };

      keys = let
        # returns {a = "no_op";} if given ["a"]
        # returns {a.b.c = "no_op";} if given ["a" "b" "c"]
        mk_no_op = path_nodes: let
          node = builtins.head path_nodes;
          is_leaf_node = builtins.length path_nodes == 1;
        in
          if is_leaf_node
          then {${node} = "no_op";}
          else {${node} = mk_no_op (builtins.tail path_nodes);};

        # returns ["a"] if given "a"
        # returns ["a" "b" "c"] if given "a.b.c"
        # returns ["a" "b" "C-."] if given "a.b.C-."
        split_path = str: let
          parts = builtins.filter (p: p != []) (builtins.split "\\." str);
          trailing_dot = builtins.substring ((builtins.stringLength str) - 1) 1 str == ".";
        in
          if trailing_dot
          then parts ++ ["."]
          else parts;

        # returns {a = "no_op";} if given "a"
        # returns {a.b.c = "no_op";} if given "a.b.c"
        # returns {a.b = {"C-." = "no_op";};} if given "a.b.C-."
        to_no_op = str: mk_no_op (split_path str);
        unbind = keys: (builtins.foldl' lib.attrsets.recursiveUpdate {} (map to_no_op keys));
        with_unbound = keys: bindings: lib.attrsets.recursiveUpdate (unbind keys) bindings;
        with_unbound_defaults = with_unbound [
          "%"
          "&"
          ";"
          "="
          "A-("
          "A-)"
          "A-,"
          "A-:"
          "A-;"
          "A-C"
          "A-S-j"
          "A-U"
          # "A-."
          "A-_"
          "A-`"
          "A-d"
          "A-down"
          "A-i"
          "A-left"
          "A-minus"
          "A-o"
          "A-p"
          "A-right"
          "A-s"
          "A-u"
          "A-up"
          "A-x"
          "A-|"
          "C-a"
          "C-b"
          "C-d"
          "C-s"
          "C-u"
          "G"
          "I"
          "N"
          "Z.C-b"
          "Z.C-d"
          "Z.C-f"
          "Z.C-u"
          "Z.K"
          "Z.k"
          "Z.pagedown"
          "Z.pageup"
          "_"
          "`"
          "end"
          "g.a"
          "g.b"
          "g.c"
          "g.f"
          "g.h"
          "g.j"
          "g.k"
          "g.l"
          "g.p"
          "g.s"
          "home"
          "j"
          "pagedown"
          "pageup"
          "space.D"
          "space.F"
          "space.S"
          "space.d"
          "space.k"
          "space.r"
          "space.w.H"
          "space.w.J"
          "space.w.K"
          "space.w.L"
          "space.w.h"
          "space.w.j"
          "space.w.k"
          "space.w.l"
          "z.C-b"
          "z.C-d"
          "z.C-f"
          "z.C-u"
          "z.K"
          "z.k"
          "z.pagedown"
          "z.pageup"
        ];

        normal = with_unbound_defaults {
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
          f = "find_next_char";
          F = "find_prev_char";
          "C-." = "repeat_last_motion";
          esc = ["collapse_selection" "keep_primary_selection"];
          C = "copy_selection_on_next_line";
          C-c = "copy_selection_on_next_line";
          A-c = "copy_selection_on_prev_line";
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
          A-e = "expand_selection";
          A-n = "shrink_selection";
          "/" = "search";
          "?" = "rsearch";
          "*" = "search_selection";
          k = "search_next";
          K = "search_prev";
          ":" = "command_mode";
          tab = "move_parent_node_end";
          S-tab = "move_parent_node_start";

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
          A-E = "increment";
          A-N = "decrement";

          # macros
          q = "record_macro";
          Q = "replay_macro";

          # sending selected contents to shell
          "|" = "shell_pipe"; # replaces selection with shell output
          "C-|" = "shell_pipe_to"; # ignores shell output
          "!" = "shell_insert_output"; # prepends shell output
          "C-!" = "shell_append_output"; # appends shell output
          "$" = "shell_keep_pipe"; # filters selections, keeps any where shell returns status of 0

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
          g.I = "goto_implementation";
          g.p = "goto_implementation";
          g.r = "goto_reference";

          # go "to" vim unimpared-ish syntax aware moves
          # go "to" next
          g.t.n.c = "goto_next_comment";
          g.t.n.C = "goto_next_class";
          g.t.n.d = "goto_next_diag";
          g.t.n.f = "goto_next_function";
          g.t.n.t = "goto_next_test";
          g.t.n.p = "goto_next_parameter";
          g.t.n.P = "goto_next_paragraph";
          # go "to" prev
          g.t.e.c = "goto_prev_comment";
          g.t.e.C = "goto_prev_class";
          g.t.e.d = "goto_prev_diag";
          g.t.e.f = "goto_prev_function";
          g.t.e.t = "goto_prev_test";
          g.t.e.p = "goto_prev_parameter";
          g.t.e.P = "goto_prev_paragraph";

          # goto changes
          g.c.c = "goto_last_change";
          g.c.f = "goto_first_change";
          g.c.n = "goto_next_change";
          g.c.e = "goto_prev_change";

          # match mode
          h.h = "match_brackets";
          h.s = "surround_add";
          h.r = "surround_replace";
          h.d = "surround_delete";
          h.a = "select_textobject_around";
          h.i = "select_textobject_inner";

          # view mode
          # z is like a normal minor mode
          # Z is like a "sticky" variant of the same mode
          # this is hardcoded in helix right now.
          z.c = "align_view_center";
          Z.c = "align_view_center";
          z.z = "align_view_center";
          Z.z = "align_view_center";
          z.E = "align_view_top";
          Z.E = "align_view_top";
          z.N = "align_view_bottom";
          Z.N = "align_view_bottom";
          z.n = "scroll_down";
          Z.n = "scroll_down";
          z.e = "scroll_up";
          Z.e = "scroll_up";

          # text "actions" minor mode
          space.a = {
            a = "align_selections"; # aligns text in columns
            c = "toggle_comments";
            l = "switch_to_lowercase";
            s = ["split_selection_on_newline" ":sort" "collapse_selection" "keep_primary_selection"];
            u = "switch_to_uppercase";
            U = ":pipe ${pkgs.titlecase}/bin/titlecase";
            S = ["split_selection_on_newline" ":rsort" "collapse_selection" "keep_primary_selection"];
            n = "add_newline_below";
            e = "add_newline_above";
            r = ":reflow";
          };

          # "buffer" minor mode
          space.b = {
            b = "buffer_picker";
            e = ":buffer-previous";
            n = ":buffer-next";
            d = ":buffer-close";
            D = ":buffer-close!";
            f = "file_picker_in_current_buffer_directory";
            N = ":new"; # open new "scratch" buffer in place
            v = ":vsplit-new"; # open new "scratch" buffer in a vsplit
            h = ":hsplit-new"; # open new "scratch" buffer in a horizontal split
            w = ":write";
            W = ":write!";
            r = ":reload";
            R = ":reload-all";
            s = ":write";
            S = ":write!";
            c.a = ":buffer-close-all";
            c.A = ":buffer-close-all!";
            c.o = ":buffer-close-others";
            c.O = ":buffer-close-others!";
          };

          # for muscle memory
          space.f.f = "file_picker";
          space.f.F = "file_picker_in_current_directory";
          space.f.b = "file_picker_in_current_buffer_directory";
          space.f.c = "changed_file_picker";
          space.f.s = ":write";

          # "git" minor mode
          space.g =
            {
              b = ":sh git branch";
              s = ":sh git status";
              p = ":sh pre-commit";
            }
            // (
              if config.programs.kitty.enable
              then {
                g = launch_gitui_overlay;
              }
              else {}
            );

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
            q = ":lsp-restart";
            Q = ":lsp-stop";
            w = ":lsp-workspace-command";
          };

          # "open" minor mode
          space.o =
            {}
            // (
              if config.programs.kitty.enable
              then {
                g = launch_gitui_overlay;
                t = ":sh kitten @ launch --type=window --cwd=current";
                T = ":sh kitten @ launch --type=os-window --cwd=current";
                tab = ":sh kitten @ launch --type=tab --cwd=current";
              }
              else {}
            );

          space.r = {
            b = just "build";
            B = just "--show build";
            c = just "check";
            C = just "--show check";
            f = just "format";
            F = just "--show format";
            j = just "--list";
            J = [":sh touch .chris.just" ":open .chris.just"];
            l = just "lint";
            L = just "--show lint";
            t = just "test";
            T = just "--show test";
          };

          # "selections" minor mode for advanced selection stuff
          space.s = {
            a = "select_all";
            n = "rotate_selections_forward";
            e = "rotate_selections_backward";
            f = "flip_selections";
            F = "ensure_selections_forward";
            k = "keep_primary_selection";
            K = "remove_primary_selection";
            minus = "remove_primary_selection";
            d = "remove_primary_selection";
            m = "merge_consecutive_selections";
            M = "merge_selections";
            r = "keep_selections"; # exclude selections that dont match a regex
            R = "remove_selections"; # exclude selections that do match a regex
            s = "split_selection";
            x = "shrink_to_line_bounds";
            q = "collapse_selection";
            "," = "collapse_selection";
            space = "trim_selections";
            "/" = "search_selection";
            t.b = "extend_prev_word_end";
            t.B = "extend_prev_long_word_end";
            t.e = "extend_next_word_end";
            t.E = "extend_next_long_word_end";
          };

          # "toggle" minor mode
          space.t = {
            b = ":toggle bufferline never always";
            c = "toggle_comments";
            C = [":toggle cursorline" ":toggle cursorcolumn"];
            w = ":toggle soft-wrap.enable";
            h = ":toggle lsp.display-inlay-hints";
            s = ":toggle whitespace.render all none";
            i = ":toggle indent-guides.render";
            N = ":set gutters.layout ${builtins.toJSON gutters}";
            n = let gs = gutters ++ ["spacer" "line-numbers"]; in ":set gutters.layout ${builtins.toJSON gs}";
            r = ":toggle line-number absolute relative";
            T = ":theme rose_pine_moon";
            t = ":theme rose_pine_dawn";
            m = ":toggle mouse";
            G = ":set statusline.center ${builtins.toJSON statusline.center}";
            g = let i = statusline.center ++ ["version-control"]; in ":set statusline.center ${builtins.toJSON i}";
            f.h = ":toggle file-picker.hidden";
            f.g = ":toggle file-picker.ignore";
          };

          # "quit" minor mode
          space.q = {
            w = ":write-quit";
            W = ":write-quit!";
            a = ":write-quit-all";
            A = ":write-quit-all!";
            q = ":quit";
            Q = ":quit!";
          };

          # minor-mode "window"
          space.w = {
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

          # "kitty" mode
          space.k = lib.mkIf config.programs.kitty.enable {
            # toggle between stack layout to emulate "full" screen
            f = ":sh kitten @ last-used-layout";
            n = ":sh kitten @ focus-window --match neighbor:bottom";
            e = ":sh kitten @ focus-window --match neighbor:top";
            m = ":sh kitten @ focus-window --match neighbor:left";
            i = ":sh kitten @ focus-window --match neighbor:right";
          };
        };
      in {
        inherit normal;
        select =
          lib.attrsets.recursiveUpdate normal
          {
            B = "extend_prev_long_word_start";
            E = "extend_next_word_end";
            F = "extend_prev_char";
            K = "extend_search_prev";
            W = "extend_next_long_word_start";
            b = "extend_prev_word_start";
            e = "extend_visual_line_up";
            esc = "normal_mode";
            f = "extend_till_char";
            g.e = "extend_line_up";
            g.n = "extend_line_down";
            i = "extend_char_right";
            k = "extend_search_next";
            m = "extend_char_left";
            n = "extend_visual_line_down";
            w = "extend_next_word_start";
            tab = "extend_parent_node_end";
            S-tab = "extend_parent_node_start";
            space.r.t = [":pipe-to echo $(cat) > /tmp/helix-just.txt" (just "test-args")];
          };
        insert =
          with_unbound [
            "A-backspace"
            "A-d"
            "A-del"
            "C-a"
            "C-d"
            "C-h"
            "C-j"
            "C-k"
            "C-r"
            "C-s"
            "C-u"
            "C-w"
            "C-x"
            "end"
            "esc"
            "home"
            "pagedown"
            "pageup"
          ] {
            esc = "normal_mode";
            ret = "insert_newline";
            "C-x" = "completion";
            "A-n" = "completion";
            "C-s" = "commit_undo_checkpoint";
            "C-p" = "insert_register";
            # C-r for consistency with non-remapple parts of helix
            "C-r" = "insert_register";
            "C-e" = "move_line_up";
            "C-n" = "move_line_down";
            "C-m" = "move_char_left";
            "C-i" = "move_char_right";
            # common readline bindings
            "A-d" = "delete_word_forward";
            "C-d" = "delete_char_forward";
            "C-k" = "kill_to_line_end";
            "C-u" = "kill_to_line_start";
            "C-w" = "delete_word_backward";
            "up" = "move_line_up";
            "down" = "move_line_down";
            "left" = "move_char_left";
            "right" = "move_char_right";
            S-tab = "move_parent_node_start";
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
