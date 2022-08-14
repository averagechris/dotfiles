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
  config.systemd.user.services.mega-cmd-server-init = {
    Unit.Description = "Try to start mega-cmd when sway starts.";
    Install.WantedBy = ["graphical-session.target"];
    Service.Type = "oneshot";
    Service.ExecStart = "${pkgs.megacmd}/bin/mega-cmd-server";
  };
}
