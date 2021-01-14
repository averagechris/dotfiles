{ config, pkgs, ... }:

{

  imports = [
    ./neovim
    ./tmux
    ./zsh
  ];

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
    htop
    lastpass-cli
    neofetch
    ripgrep
    signal-desktop
    source-code-pro
    tree
    wget
    write_stylus
    xclip
  ];

  programs.git = {
    enable = true;
    userName = "Chris Cummings";
    userEmail = "chris@thesogu.com";
    extraConfig = {
      pull.rebase = true;
    };
  };

  programs.mu.enable = true;
}
