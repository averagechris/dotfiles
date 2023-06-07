{
  lib,
  pkgs,
  sshKeys,
  input-modules,
  ...
}: let
  userName = "chris";
in {
  programs.zsh.enable = true;
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
      ../../../hm_modules
      input-modules.doom
    ];
    dotfiles.shell.enable = true;
    dotfiles.shell.python.enable = true;
  };
}
