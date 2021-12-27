{ config, pkgs, lib, ... }:
let
  groups = [
    "networkmanager"
    "wheel"
  ];
in
{
  users.users = {
    chris-focus = {
      isNormalUser = true;
      extraGroups = groups;
      shell = pkgs.zsh;
    };
  };
}
