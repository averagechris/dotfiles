{ pkgs, lib, ... }:

let
  path_finder = pkgs.callPackage ../../scripts/path_finder/default.nix { };

in
{
  home.packages = [
    path_finder
  ];
}
