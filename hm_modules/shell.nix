{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) isLinux;

  cfg = config.dotfiles.shell;
  mkDefaultEnabledOption = description:
    lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = lib.mdDoc description;
    };
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
    ];

    options.dotfiles.shell = {
      enable = mkEnableOption "my dotfiles shell config.";
      emacs.enable = mkEnableOption "enable my highly configured doom emacs setup.";
      neovim.enable = mkEnableOption "enable configured neovim setup.";
      nerdfonts.enable = mkEnableOption "install nerdfonts.";
      passhole.enable = mkEnableOption "Passhole is a python cli for interacting with keepass databases. I have some utilities built up around it, but in a GUI environment, keepassxc is a better tool. But this is useful for non-gui environments.";
      python.enable = mkEnableOption "Install a python interpreter with optional packages. Generally this is better off as a project level dependency, but it can be handy to have a python interpreter always at the ready. ipython package included by default.";

      # default enabled
      git.enable = mkDefaultEnabledOption "enable configured git.";
      gitui.enable = mkDefaultEnabledOption "enable gitui, configured to be integrated with zellij + helix.";
      gpg.enable = mkEnableOption "right now this only sets up the GPG_TTY env variable, but in the future it might do more.";
      helix.enable = mkDefaultEnabledOption "enable my highly configured helix.";
      shell_scripts.enable = mkDefaultEnabledOption "enable the various shell scripts i've written.";
      zellij.enable = mkDefaultEnabledOption "enable my highly configured zellij.";

      # default enabled features if the primary feature is enabled (disabled by default)
      passhole.swayIntegration.enable = mkDefaultEnabledOption "enable the wayland integration for passhole via keybindings for bemenu.";

      # config values with good minimal defaults
      env.editor = mkOption {
        type = types.enum ["hx" "nvim" "vim" "emacsclient -t" "emacs"];
        default =
          if cfg.helix.enable
          then "hx"
          else "nvim";
        example = "emacsclient -t";
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
      programs.direnv.enable = true;
      programs.direnv.nix-direnv.enable = true;
      programs.doom-emacs.enable = cfg.emacs.enable;
      programs.fzf.enable = true;
      programs.git.enable = cfg.git.enable;
      programs.gitui.enable = true;
      programs.helix.enable = cfg.helix.enable;
      programs.neovim.enable = cfg.neovim.enable;
      programs.starship.enable = true; # shell prompt
      programs.zellij.enable = cfg.zellij.enable;
      programs.zsh.enable = true;
      programs.zsh.oh-my-zsh.enable = true;

      services.emacs.enable = cfg.emacs.enable;

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
          direnv
          fd
          htop
          jq
          pre-commit
          procs
          ripgrep
        ]
        ++ (
          if cfg.shell_scripts.enable
          then extra_shell_scripts
          else []
        );
    };
  }
