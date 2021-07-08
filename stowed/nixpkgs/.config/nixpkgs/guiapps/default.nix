{ config, pkgs, ... }:

{
  if pkgs.stdenv.hostPlatform.isLinux then
    home.packages = with pkgs; [
      signal-desktop
      write_stylus
    ];
}
