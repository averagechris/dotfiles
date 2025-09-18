{
  config,
  lib,
  pkgs,
  inputs,
  dotfiles_lib,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) isLinux;

  cfg = config.dotfiles.shell;
  extra_shell_scripts = builtins.attrValues (import ./shell_modules/shell_extras.nix {inherit pkgs;});
in
  with lib; {
    imports = [
      ../hm_modules/zellij
      ./git
      ./gitui
      ./neovim
      ../nixpkgs/python
      ./shell_modules/calibre-utils.nix
      ./shell_modules/fzf.nix
      ./shell_modules/lazygit.nix
      ./shell_modules/less.nix
      ./shell_modules/pipx.nix
      ./shell_modules/ranger.nix
      ./shell_modules/yazi.nix
      ./shell_modules/zsh.nix
    ];

    options.dotfiles.shell = with dotfiles_lib.options; {
      enable = mkDefaultEnabledOption "enables the my shell configuration.";
      python.enable = mkEnableOption "Install a python interpreter with optional packages. Generally this is better off as a project level dependency, but it can be handy to have a python interpreter always at the ready. ipython package included by default.";
      yazi.enable = mkEnableOption "Yazi is a terminal file manager with vim-like keybindings and customized for Colemak keyboard layout.";

      # default enabled
      gpg.enable = mkEnableOption "right now this only sets up the GPG_TTY env variable, but in the future it might do more.";
      shell_scripts.enable = mkDefaultEnabledOption "enable the various shell scripts i've written.";

      # config values with good minimal defaults
      env.editor = mkOption {
        type = types.enum ["hx" "nvim" "vim"];
        default =
          if config.programs.helix.enable
          then "hx"
          else "nvim";
        example = "hx";
        description = "The shell command used as the EDITOR environment variable.";
      };

      commands = {
        copy = mkOption {
          type = types.str;
          default =
            if isLinux
            then "${pkgs.wl-clipboard}/bin/wl-copy"
            else "pbcopy";
          example = "pbcopy";
          description = ''
             The shell command used to send data to the system clipboard
            It can be the full path, or just the command name if it's installed
            in your shell environment's $PATH variable.

            The default value assumes you're using wayland on linux.
          '';
        };
        paste = mkOption {
          type = types.str;
          default =
            if isLinux
            then "${pkgs.wl-clipboard}/bin/wl-paste"
            else "pbpaste";
          example = "pbpaste";
          description = ''
             The shell command used to send data to the system clipboard
            It can be the full path, or just the command name if it's installed
            in your shell environment's $PATH variable.

            The default value assumes you're using wayland on linux.
          '';
        };
      };
    };

    config = mkIf cfg.enable {
      programs.fzf.enable = lib.mkDefault true;
      programs.git.enable = lib.mkDefault true;
      programs.gitui.enable = lib.mkDefault true;
      programs.helix.enable = lib.mkDefault true;
      programs.lazygit.enable = lib.mkDefault true;
      programs.starship.enable = lib.mkDefault true;
      programs.zellij.enable = lib.mkDefault true;
      programs.zsh.enable = lib.mkDefault true;
      programs.zsh.oh-my-zsh.enable = lib.mkDefault true;
      programs.jq.enable = lib.mkDefault true;
      dotfiles.yazi.enable = lib.mkDefault true;

      # Starship prompt: prefer jj (Jujutsu) when available, fall back to git.
      # Use programs.starship.settings instead of writing a file.
      programs.starship.settings = lib.mkDefault (let
        starshipJj = inputs.starship-jj.packages.${pkgs.system}.default;
      in {
        "$schema" = "https://starship.rs/config-schema.json";
        format = "$directory\${custom.jj}\${custom.env} $all";
        git_branch = {disabled = true;};
        git_commit = {disabled = true;};
        git_state = {disabled = true;};
        git_status = {disabled = true;};
        git_metrics = {disabled = true;};
        vcsh = {disabled = true;};
        command_timeout = 1200;
        aws = {disabled = true;}; # hide AWS module
        nix_shell = {disabled = true;};
        package = {
          format = "[$symbol$version]($style) ";
          symbol = "📦";
        };
        rust = {
          format = "[$symbol$version]($style) ";
          symbol = "🦀";
        };
        custom = {
          jj = {
            description = "jj via starship-jj plugin";
            format = "$output ";
            ignore_timeout = true;
            when = true;
            use_stdin = false;
            # call the flake-provided binary via inputs
            shell = [
              "${starshipJj}/bin/starship-jj"
              "--ignore-working-copy"
              "starship"
            ];
            command = "prompt";
          };

          env = {
            description = "Show activated dev envs (direnv/mise/nix)";
            when = "[ -n \"$DIRENV_DIR\" ] || [ -n \"$MISE_ACTIVE\" ] || [ -n \"$NIX_ENVIRONMENT\" ] || [ -n \"$IN_NIX_SHELL\" ]";
            use_stdin = false;
            shell = ["sh" "-lc"];
            command = ''
              direnv=""
              mise=""
              out=""
              if [ -n "''${DIRENV_DIR-}" ]; then direnv="direnv"; fi
              if [ -n "''${MISE_ACTIVE-}" ]; then mise="mise"; fi

              nix=""
              if [ -n "''${NIX_SHELL_NAME-}" ]; then
                nix="nix:''${NIX_SHELL_NAME}"
              elif [ -n "''${NIX_ENVIRONMENT-}" ]; then
                nix="nix:''${NIX_ENVIRONMENT}"
              elif [ -n "''${IN_NIX_SHELL-}" ]; then
                nix="nix"
              fi

              if [ -n "$nix" ]; then
                if [ -n "$direnv" ]; then
                  direnv="$direnv($nix)"
                elif [ -n "$mise" ]; then
                  mise="$mise($nix)"
                else
                  out="$nix"
                fi
              fi

              if [ -n "$direnv" ]; then
                out="$direnv"
              fi
              if [ -n "$mise" ]; then
                if [ -n "$out" ]; then out="$out $mise"; else out="$mise"; fi
              fi

              printf '%s' "$out"
            '';
            format = "[$output](bold blue) ";
          };
        };
      });

      programs.ripgrep = {
        enable = lib.mkDefault true;
        arguments = [
          "--max-columns-preview"
          "--colors=line:style:bold"
        ];
      };

      programs.direnv = {
        enable = lib.mkDefault true;
        nix-direnv.enable = lib.mkDefault true;
        enableZshIntegration = lib.mkDefault true;
        enableNushellIntegration = lib.mkDefault true;
      };

      programs.htop = {
        enable = lib.mkDefault true;
        settings =
          {
            color_scheme = 6;
            cpu_count_from_one = 0;
            delay = 15;
            fields = with config.lib.htop.fields; [
              PID
              USER
              PRIORITY
              NICE
              M_SIZE
              M_RESIDENT
              M_SHARE
              STATE
              PERCENT_CPU
              PERCENT_MEM
              TIME
              COMM
            ];
            highlight_base_name = 1;
            highlight_megabytes = 1;
            highlight_threads = 1;
          }
          // (with config.lib.htop;
            leftMeters [
              (bar "AllCPUs2")
              (bar "Memory")
              (bar "Swap")
              (text "Zram")
            ])
          // (with config.lib.htop;
            rightMeters [
              (text "Tasks")
              (text "LoadAverage")
              (text "Uptime")
              (text "Systemd")
            ]);
      };

      programs.jujutsu = {
        enable = true;
        settings.user = {
          name = "chris";
          email = "chris@thesogu.com";
        };
      };

      home.sessionVariables = mkMerge [
        {
          EDITOR = cfg.env.editor;
          GIT_EDITOR = cfg.env.editor;
        }
        (mkIf cfg.gpg.enable {
          GPG_TTY = "$(tty)";
        })
      ];

      home.packages = with pkgs;
        [
          curl
          fd
          just
          pre-commit
          procs
          titlecase
        ]
        ++ (
          if cfg.shell_scripts.enable
          then extra_shell_scripts
          else []
        );
    };
  }
