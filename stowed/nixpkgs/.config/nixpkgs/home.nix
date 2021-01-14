{ config, lib, pkgs, ... }:

let
  spacevim = pkgs.fetchgit {
    url = "https://github.com/SpaceVim/SpaceVim.git";
    rev = "d870c6a1bc91437e77fee9eae62f67ef4cef6371";
    sha256 = "1c884yq5ihxj9qgsjbkwkffa3f5lcmkbnghws6gkkfsv8y66s1s1";
  };

in {

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "chris";
  home.homeDirectory = "/home/chris";

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "21.03";

  home.packages = with pkgs; [
    curl
    emacs
    fd
    fzf
    ispell
    gcc
    gnumake
    gnutls
    lastpass-cli
    neofetch
    ripgrep
    signal-desktop
    tree
    wget
    xclip
    xsel
  ];

  programs.htop.enable = true;
  programs.git = {
    enable = true;
    userName = "Chris Cummings";
    userEmail = "chris@thesogu.com";
    extraConfig = {
      pull.rebase = true;
    };
  };

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

  programs.neovim = {
    enable = true;
    vimAlias = true;
    extraConfig = ''
      execute 'source' '${spacevim}/config/main.vim'
    '';
  };

  programs.mu.enable = true;
}