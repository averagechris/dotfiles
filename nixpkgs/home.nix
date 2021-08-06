{ config, pkgs, ... }:

{
  imports = [ ./localhome ];

  home.stateVersion = "21.05";
  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    extraConfig = { pull.rebase = true; };
    # these are be defined in localhome.default.nix
    # userName
    # userEmail
  };

}
