{ config, pkgs, ... }:

{
  config.home.packages = [ pkgs.megacmd ];
}
