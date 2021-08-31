{ pkgs, config, lib, ... }:

let
  # TODO why does using `pkgs` here cause an infinite recursion?
  # this works just seems ugly 🤷🤷🤷
  isLinux = (import <nixpkgs> {}).stdenv.hostPlatform.isLinux;
in
if isLinux then
  import ./sway { pkgs = pkgs; config = config; lib = lib; }
else {
  # TODO yabai & skhd or keep them in nix-darwin?
}
