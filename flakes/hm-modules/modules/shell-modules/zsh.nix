{
  config,
  lib,
  ...
}: let
  cfg = config.dotfiles.shell;
in
  with lib; {
    options = {};

    config = mkIf cfg.enable {
      programs.zsh = {
        # NOTE: dotDir is being moved to "${config.xdg.configHome}/zsh" eventually
        dotDir = mkDefault config.home.homeDirectory;
        envExtra = ''
          export PATH="$HOME/.nix-profile/bin:$PATH"
        '';
        history = {
          size = 50000;
          ignoreDups = true;
        };

        autosuggestion.enable = true;
        enableCompletion = true;

        "oh-my-zsh" = {
          theme = "clean";
        };

        sessionVariables.LESS = "-SRXF";

        shellAliases = {
          cp = "cp -iv";
          mv = "mv -iv";
          mkdir = "mkdir -pv";
          pbcopy = config.dotfiles.shell.commands.copy;
          pbpaste = config.dotfiles.shell.commands.paste;
          nixos-switch = "nixos-rebuild switch --use-remote-sudo";
          nixos-test = "nixos-rebuild test --use-remote-sudo";
          nixos-build = "nixos-rebuild build";
          today = "date +%Y-%m-%d";
          tailscale-set-exit-node = ''
            tailscale set --exit-node="$(tailscale exit-node list | tr -s ' ' | cut -d ' ' -f 3 | fzf)"
          '';
        };
      };
    };
  }
