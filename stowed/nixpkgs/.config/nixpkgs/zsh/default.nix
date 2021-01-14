{ config, pkgs, ... }:

{
  programs.zsh = {
    enable = true;

    defaultKeymap = "viins";

    history = {
      size = 50000;
      ignoreDups = true;
    };

    initExtra = builtins.readFile ./post-compinit.zsh;
    shellAliases = import ./aliases.nix;

    enableAutosuggestions = true;
    enableCompletion = true;

    oh-my-zsh = {
      enable = true;
      theme="clean";
      plugins = [
        "git"
      ];
    };

    sessionVariables = rec {
        EDITOR = "emacsclient -t";
        FZF_CTRL_T_COMMAND = "fd";
        FZF_DEFAULT_COMMAND = "fd";
        GIT_EDITOR = EDITOR;
        KEYTIMEOUT = "1";
        LESS = "-SRXF";
        VISUAL = "emacs";
    };

  };
}