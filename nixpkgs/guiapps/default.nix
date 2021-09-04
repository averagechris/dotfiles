{ config, pkgs, ... }:

let

  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  apple-music-electron = pkgs.callPackage ./apple-music-electron.nix { };

in
{
  home.packages =
    if isLinux then
      with pkgs; [
        apple-music-electron
        signal-desktop
        write_stylus
      ] else [ ];
}
