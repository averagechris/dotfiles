{ config, pkgs, ... }:

let

  isLinux = pkgs.stdenv.hostPlatform.isLinux;

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
