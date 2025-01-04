{pkgs, ...}: let
  userName = "christiana";
in {
  users.users = {
    "${userName}" = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
      ];
      shell = pkgs.zsh;
    };
  };
  home-manager.users."${userName}" = {...}: {
    home = {
      username = userName;
      homeDirectory = "/home/${userName}";
    };
    imports = [../../../hm_modules];
  };
}
