{
  config,
  lib,
  pkgs,
  dotfiles_lib,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) isLinux;

  cfg = config.dotfiles.shell;
  extra_shell_scripts = builtins.attrValues (import ../nixpkgs/shell/shell_extras.nix {inherit pkgs;});
in
  with lib; {
    imports = [
      ../nixpkgs/helix.nix
      ../nixpkgs/zellij
      ../nixpkgs/shell
      ../nixpkgs/gitui
      ../nixpkgs/nerdfonts
      ../nixpkgs/neovim
      ../nixpkgs/git
      ../nixpkgs/passhole
      ../nixpkgs/python
      ./shell_modules/less.nix
      ./shell_modules/ranger.nix
      ./shell_modules/pipx.nix
      ./shell_modules/lazygit.nix
      ./shell_modules/calibre-utils.nix
      ./shell_modules/yazi.nix
    ];

    options.programs.pijul = {
      enable = mkEnableOption "enable the pijul package manager.";
      enableBashIntegration = mkEnableOption "install pijul bash completions";
      enableZshIntegration = mkEnableOption "install pijul zsh completions";
    };

    options.dotfiles.shell = with dotfiles_lib.options; {
      enable = mkDefaultEnabledOption "enables the my shell configuration.";
      nerdfonts.enable = mkEnableOption "install nerdfonts.";
      passhole.enable = mkEnableOption "Passhole is a python cli for interacting with keepass databases. I have some utilities built up around it, but in a GUI environment, keepassxc is a better tool. But this is useful for non-gui environments.";
      python.enable = mkEnableOption "Install a python interpreter with optional packages. Generally this is better off as a project level dependency, but it can be handy to have a python interpreter always at the ready. ipython package included by default.";
      yazi.enable = mkEnableOption "Yazi is a terminal file manager with vim-like keybindings and customized for Colemak keyboard layout.";

      # default enabled
      gpg.enable = mkEnableOption "right now this only sets up the GPG_TTY env variable, but in the future it might do more.";
      shell_scripts.enable = mkDefaultEnabledOption "enable the various shell scripts i've written.";

      # default enabled features if the primary feature is enabled (disabled by default)
      passhole.swayIntegration.enable = mkEnableOption "enable the wayland integration for passhole via keybindings for bemenu.";

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

      nerdfonts.fonts = mkOption {
        type = with types; listOf str;
        example = ["DroidSaansMono"];
        default = [
          "FiraCode"
          "DroidSansMono"
          "Overpass"
        ];
        description = "The list of fonts installed and added to ~/.config/fonts/nerdfonts";
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
      # pijul completions
      programs.bash.initExtra = mkIf config.programs.pijul.enableBashIntegration ''
        source ${pkgs.pijul}/share/bash-completion/completions/pijul.bash
      '';
      programs.zsh.initExtra = mkIf config.programs.pijul.enableZshIntegration ''
        source ${pkgs.pijul}/share/zsh/site-functions/_pijul
      '';

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
          if config.programs.pijul.enable
          then [pijul]
          else []
        )
        ++ (
          if cfg.shell_scripts.enable
          then extra_shell_scripts
          else []
        );
    };
  }
