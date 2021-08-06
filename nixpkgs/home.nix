{ config, pkgs, ... }:

{
  home.stateVersion = "21.05";
  programs.home-manager.enable = true;
  imports = [ ./localhome ];
}
