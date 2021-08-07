{ config, pkgs, ... }:

let
  userName = "<username>";
  homeDirectory = "/Users/<username>";
in {
  users.users."${userName}" = {
    name = "${userName}";
    home = "${homeDirectory}";
  };

  # this is responsible for hooking up all of our home-manager config
  home-manager.users."${userName}" = { pkgs, ... }: {
    imports = [ ../home.nix ];
  };
}
