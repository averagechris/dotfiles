{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  isHelixEnabled = config.programs.helix.enable;
  isGPGenabled = true; # 😂 FIXME: config points to home-manager here, but need nixos's config?
  EDITOR =
    if isHelixEnabled
    then "hx"
    else "vim";
in {
  # starship is the shell prompt
  programs.starship.enable = true;

  programs.zsh = {
    enable = true;

    history = {
      size = 50000;
      ignoreDups = true;
    };

    initExtra = (builtins.readFile ./post-compinit.zsh) + ''eval "$(${pkgs.direnv}/bin/direnv hook zsh)"'';

    shellAliases = import ./aliases.nix {inherit pkgs;};

    enableAutosuggestions = true;
    enableCompletion = true;

    oh-my-zsh = {
      enable = true;
      theme = "clean";
    };

    sessionVariables = lib.mkMerge [
      {
        inherit EDITOR;
        GIT_EDITOR = EDITOR;
        KEYTIMEOUT = "1";
        LESS = "-SRXF";
      }
      (lib.mkIf isGPGenabled {
        GPG_TTY = "$(tty)";
      })
    ];
  };

  programs.fzf = {
    enable = true;
    defaultCommand = "fd --type f";
    defaultOptions = [
      "--color=fg:#908caa,bg:#232136,hl:#ea9a97"
      "--color=fg+:#e0def4,bg+:#393552,hl+:#ea9a97"
      "--color=border:#44415a,header:#3e8fb0,gutter:#232136"
      "--color=spinner:#f6c177,info:#9ccfd8,separator:#44415a"
      "--color=pointer:#c4a7e7,marker:#eb6f92,prompt:#908caa"
    ];
    fileWidgetCommand = "fd --type f --hidden";
    changeDirWidgetCommand = "fd --type d";
    enableZshIntegration = true;
  };

  home.packages = with pkgs;
    [
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
    ]
    ++ (
      if isLinux
      then builtins.attrValues (import ./shell_extras.nix {inherit pkgs;})
      else []
    );
}
