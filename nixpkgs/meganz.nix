{
  config,
  pkgs,
  ...
}: let
  gui =
    if config.wayland.windowManager.sway.enable
    then [pkgs.megasync]
    else [];
in {
  config.home.packages = with pkgs; [megacmd] ++ gui;
}
