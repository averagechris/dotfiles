{
  config,
  inputs,
  lib,
  pkgs,
  system,
  ...
}: let
  cfg = config.programs.helix;
  baseHelixPackage = inputs.helix.packages.${system}.default;
  baseHelixRuntime = baseHelixPackage.HELIX_DEFAULT_RUNTIME;
  helixGrammarExtension = pkgs.stdenv.hostPlatform.extensions.sharedLibrary;
  trimmedHelixRuntime = pkgs.runCommand "helix-runtime-curated-grammars" {} ''
    mkdir -p "$out/grammars"

    for dir in queries themes; do
      if [[ -d "${baseHelixRuntime}/$dir" ]]; then
        cp -R --no-preserve=ownership "${baseHelixRuntime}/$dir" "$out/$dir"
      fi
    done

    if [[ -e "${baseHelixRuntime}/tutor" ]]; then
      cp -R --no-preserve=ownership "${baseHelixRuntime}/tutor" "$out/tutor"
    fi

    for grammar in ${lib.escapeShellArgs cfg.grammarPackageNames}; do
      src="${baseHelixRuntime}/grammars/$grammar${helixGrammarExtension}"
      if [[ -e "$src" ]]; then
        cp --no-preserve=ownership "$src" "$out/grammars/"
      else
        echo "missing Helix grammar: $grammar" >&2
        exit 1
      fi
    done
  '';
  helixPackage =
    pkgs.runCommand "${baseHelixPackage.name}-curated-grammars" {
      inherit (baseHelixPackage) meta;
      nativeBuildInputs = [pkgs.makeWrapper pkgs.removeReferencesTo];
    } ''
      mkdir -p "$out"
      cp -R --no-preserve=ownership ${baseHelixPackage}/. "$out"
      chmod -R u+w "$out"
      rm -f "$out/nix-support/propagated-build-inputs"

      if [[ -x "$out/bin/hx" ]]; then
        remove-references-to -t ${baseHelixRuntime} "$out/bin/hx"
        wrapProgram "$out/bin/hx" \
          --set HELIX_RUNTIME ${trimmedHelixRuntime}
      fi
    '';
  gutters = ["diagnostics" "spacer" "diff"];
  statusline.center = [];

  # Terminal flavor detection
  terminalFlavor =
    if config.programs.helix.terminal.flavor == "wezterm"
    then "wezterm"
    else "kitty";
in {
  options.programs.helix = {
    terminal = {
      flavor = lib.mkOption {
        type = lib.types.enum ["kitty" "wezterm"];
        default = "wezterm";
        description = "Terminal flavor to use for terminal integration features";
      };
    };

    grammarPackageNames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        # Core daily languages.
        "bash"
        "gleam"
        "nix"
        "python"
        "rust"
        "rust-format-args"
        "shellcheckrc"

        # Web/frontend ecosystems.
        "astro"
        "css"
        "graphql"
        "html"
        "javascript"
        "jsdoc"
        "json"
        "json5"
        "markdown"
        "markdown_inline"
        "prisma"
        "scss"
        "svelte"
        "tsx"
        "typescript"
        "vue"

        # Cloud/config/devops formats.
        "bicep"
        "caddyfile"
        "cue"
        "dockerfile"
        "git-config"
        "gitattributes"
        "gitcommit"
        "gitignore"
        "go"
        "gomod"
        "gotmpl"
        "gowork"
        "hcl"
        "hosts"
        "ini"
        "jq"
        "just"
        "make"
        "nginx"
        "pem"
        "properties"
        "rego"
        "sql"
        "ssh_client_config"
        "toml"
        "xml"
        "yaml"
      ];
      description = ''
        Helix tree-sitter grammars to keep in the managed runtime. The default is
        a broad daily-driver set for Rust, Python, Nix, shell scripts, web
        development, and cloud/config files without the full upstream long tail
        of obscure languages.
      '';
    };
  };

  config.programs.helix = lib.mkIf cfg.enable {
    package = lib.mkDefault helixPackage;
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
