{ pkgs, config, ... }:

let
  # TODO why does using `pkgs` here cause an infinite recursion?
  # this works just seems ugly 🤷🤷🤷
  isLinux = (import <nixpkgs> {}).stdenv.hostPlatform.isLinux;
in
if isLinux then
  import ./alacritty.nix { pkgs = pkgs; config = config; }
else {}
