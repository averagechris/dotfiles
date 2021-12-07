{ config, pkgs, lib, ... }:
let
  groups = [
    "networkmanager"
    "wheel"
  ];
in
{
  users.users = {
    chris = {
      isNormalUser = true;
      extraGroups = groups;
      shell = pkgs.zsh;
    };
    chris-focus = {
      isNormalUser = true;
      extraGroups = groups;
      shell = pkgs.zsh;
    };
  };
}
