{
  config,
  inputs,
  lib,
  pkgs,
  system,
  ...
}: let
  cfg = config.programs.helix;
  gutters = ["diagnostics" "spacer" "diff"];
  statusline.center = [];

  # Terminal flavor detection
  terminalFlavor =
    if config.programs.helix.terminal.flavor == "wezterm"
    then "wezterm"
    else "kitty";
in {
  options.programs.helix.terminal = {
    flavor = lib.mkOption {
      type = lib.types.enum ["kitty" "wezterm"];
      default = "wezterm";
      description = "Terminal flavor to use for terminal integration features";
    };
  };

  config.programs.helix = lib.mkIf cfg.enable {
    package = lib.mkDefault inputs.helix.packages.${system}.default;
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
        end-of-line-diagnostics = "hint";
        inline-diagnostics.cursor-line = "error";
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

      keys = import ./keybindings.nix {
        inherit config lib pkgs;
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
      ];
    };
  };
}
