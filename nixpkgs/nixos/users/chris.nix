{ pkgs, inputs, ... }:

let
  inherit (inputs) home-manager;
  userName = "chris";

in
{
  users.users = {
    "${userName}" = {
      isNormalUser = true;
      extraGroups = [
        "networkmanager"
        "wheel"
      ];
      shell = pkgs.zsh;
    };
  };

  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
  };

  home-manager.users."${userName}" = { pkgs, ... }: rec {
    home = {
      stateVersion = "21.05";
      username = userName;
      homeDirectory = "/home/${userName}";
    };

    programs.git = {
      userName = "Chris Cummings";
      userEmail = "chris@thesogu.com";
    };

    imports = [
      ../../emacs
      ../../firefox
      ../../git
      ../../guiapps
      ../../linux_desktop
      ../../neovim
      ../../nerdfonts
      ../../personal_scripts
      ../../python
      ../../shell
      ../../sway
      ../../terminal_emulator
      ../../tmux
      inputs.nix-doom-emacs.hmModule
    ];
  };

}
