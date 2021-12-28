{ pkgs, inputs, ... }:

let
  userName = "chris";
  home-manager = inputs.home-manager;

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
