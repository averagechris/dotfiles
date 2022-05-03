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

    initExtra = (builtins.readFile ./post-compinit.zsh) + ''
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

    (writeShellScriptBin "video_compress" ''
      ${pkgs.handbrake}/bin/HandBrakeCLI -i "$1" -o "$2" -e x264 -q 18 -a 1,1 -E faac,copy:ac3 -B 256,256 -6 dpl2,auto -R Auto,Auto -D 0.0,0.0 -f mp4 --detelecine --decomb --loose-anamorphic -m -x b-adapt=2:rc-lookahead=50
    '')
  ];

}
