{ config, pkgs, ... }:

let
  isLinux = (import <nixpkgs> {}).stdenv.hostPlatform.isLinux;
  linuxOnlyPackages = with pkgs; [ xclip ];
  darwinOnlyPackages = with pkgs; [ ];
in {
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
        GIT_EDITOR = EDITOR;
        KEYTIMEOUT = "1";
        LESS = "-SRXF";
        VISUAL = "emacs";
    };

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
    gcc
    gnumake
    gnutls
    htop
    jq
    lastpass-cli
    neofetch
    pgcli
    procs
    ripgrep
    tree
    wget
  ] ++ linuxOnlyPackages ++ darwinOnlyPackages;

}
