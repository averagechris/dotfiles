{pkgs, ...}: {
  imports = [./aliases.nix];
  programs.zsh = {
    history = {
      size = 50000;
      ignoreDups = true;
    };

    enableAutosuggestions = true;
    enableCompletion = true;

    oh-my-zsh = {
      theme = "clean";
      plugins = ["ssh-agent"];
      extraConfig = ''
        zstyle :omz:plugins:ssh-agent identities id_ed25519
      '';
    };

    sessionVariables.LESS = "-SRXF";
  };

  programs.fzf = {
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
}
