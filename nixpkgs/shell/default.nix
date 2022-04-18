{ config, pkgs, ... }:

let
  isEmacsEnabled = config.programs.doom-emacs.enable;
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

    initExtra = builtins.readFile ./post-compinit.zsh;
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
    gnutls
    htop
    jq
    neofetch
    pre-commit
    procs
    ripgrep
    shellcheck
    shfmt
    sshfs
    unzip
    wget
  ];

}
