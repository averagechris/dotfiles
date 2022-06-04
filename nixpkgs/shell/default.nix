{ config, pkgs, ... }:

let
  isEmacsEnabled = config.services.emacs.enable;
in
{
  # starship is the shell prompt
  programs.starship.enable = true;

  programs.zsh = {
    enable = true;

    defaultKeymap = "viins";

    history = {
      size = 50000;
      ignoreDups = true;
    };

    initExtra = with pkgs; (builtins.readFile ./post-compinit.zsh) + ''

      eval "$(${direnv}/bin/direnv hook zsh)"

      ph-widget() {
        ph info | grep -q 'Database Version' && ph show --field password "$(ph grep -i . | fzf)" | wl-copy --trim-newline
      }

      zle -N ph-widget
      bindkey -M emacs '^p' ph-widget
      bindkey -M vicmd '^p' ph-widget
      bindkey -M viins '^p' ph-widget
    '';

    shellAliases = import ./aliases.nix { inherit pkgs; };

    enableAutosuggestions = true;
    enableCompletion = true;

    oh-my-zsh = {
      enable = true;
      theme = "clean";
    };

    sessionVariables = rec {
      EDITOR = if isEmacsEnabled then "emacsclient -t" else "nvim";
      GIT_EDITOR = EDITOR;
      KEYTIMEOUT = "1";
      LESS = "-SRXF";
    } // (if isEmacsEnabled then {
      VISUAL = "emacs";
    } else { });

  };

  programs.fzf = {
    enable = true;
    defaultCommand = "fd --type f";
    fileWidgetCommand = "fd --type f --hidden";
    changeDirWidgetCommand = "fd --type d";
    enableZshIntegration = true;
  };

  home.packages = with pkgs; [
    curl
    direnv
    fd
    htop
    jq
    neofetch
    pre-commit
    procs
    ripgrep
    sshfs
    wget
  ] ++ builtins.attrValues (import ./shell_extras.nix { inherit pkgs; });

}
