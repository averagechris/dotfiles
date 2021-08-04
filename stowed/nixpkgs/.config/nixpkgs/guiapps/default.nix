{ config, pkgs, ... }:

let

  isLinux = pkgs.stdenv.hostPlatform.isLinux;

in
{
  home.packages =
    if isLinux then
      with pkgs; [
        signal-desktop
        write_stylus
      ] else [ ];
}
