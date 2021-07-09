{ config, pkgs, ... }:

{
  home.packages =
    if pkgs.stdenv.hostPlatform.isLinux then
      with pkgs; [
        signal-desktop
        write_stylus
      ] else [ ];
}
