{ pkgs, inputs, ... }:
let
  userName = "chris-focus";
  sure = import ../../sure { inherit pkgs inputs; };

in
{
  users.users = {
    "${userName}" = {
      isNormalUser = true;
      extraGroups = [
        "docker"
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

  home-manager.users."${userName}" = { pkgs, ... }: {
    home = {
      stateVersion = "21.05";
      username = userName;
      homeDirectory = "/home/${userName}";
    };

    programs.git = {
      userName = "Chris Cummings";
      userEmail = "chris.cummings@sureapp.com";
    };

    imports = [
      ../../emacs
      ../../firefox
      ../../git
      ../../guiapps
      ../../linux_desktop
      ../../meganz.nix
      ../../neovim
      ../../nerdfonts
      ../../passhole
      ../../personal_scripts
      ../../python
      ../../shell
      ../../sway
      ../../terminal_emulator
      ../../tmux
      inputs.nix-doom-emacs.hmModule
      sure
    ];
  };

}
