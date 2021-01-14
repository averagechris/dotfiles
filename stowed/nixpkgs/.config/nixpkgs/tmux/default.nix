{ config, pkgs, ... }:

{
  programs.tmux = {
    enable = true;
    keyMode = "vi";
    escapeTime = 0;
    aggressiveResize = true;
    terminal = "tmux-256color";
    extraConfig = builtins.readFile ./tmux.conf;
  };
}