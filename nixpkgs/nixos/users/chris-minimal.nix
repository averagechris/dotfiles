{
  pkgs,
  lib,
  sshKeys,
  ...
}: let
  userName = "chris";
in {
  users.users = {
    "${userName}" = {
      isNormalUser = true;
      extraGroups = [
        "networkmanager"
        "wheel"
      ];
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = lib.attrValues sshKeys.chris;
    };
  };

  home-manager.users."${userName}" = {...}: {
    home = {
      username = userName;
      homeDirectory = "/home/${userName}";
    };

    programs.git = {
      userName = "Chris Cummings";
      userEmail = "chris@thesogu.com";
    };

    imports = [
      ../../git
      ../../neovim
      ../../passhole
      ../../python
      ../../shell
      ../../tmux
    ];
  };
}
