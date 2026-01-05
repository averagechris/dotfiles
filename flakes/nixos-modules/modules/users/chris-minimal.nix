{
  lib,
  pkgs,
  sshKeys,
  inputs,
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

    programs.git.settings = {
      user.name = "Chris Cummings";
      user.email = "chris@thesogu.com";
    };

    imports =
      if inputs ? hm-modules
      then [inputs.hm-modules.homeManagerModules.default]
      else [../../../hm_modules];
  };
}
