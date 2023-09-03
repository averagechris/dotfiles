{
  pkgs,
  lib,
  ...
}: let
  hyprlandGreetConfig = pkgs.writeText "greetd-hyprland-config" ''
    env=GDK_BACKEND,wayland
    env=XCURSOR_SIZE,24
    exec-once="sleep 2 && ${lib.getExe pkgs.greetd.gtkgreet} -l; hyprtcl dispatch exit"
    bind=SUPER+SHIFT,Q,exec,systemctl poweroff
    bind=SUPER+SHIFT,R,exec,systemctl reboot
    bind=SUPER,R,exec,${lib.getExe pkgs.greetd.gtkgreet} -l; hyprtcl dispatch exit
    input {
      touchpad {
        clickfinger_behavior=true
      }
      numlock_by_default=true
    }
    animations {
      bezier=windowBezier, 0.05, 0.9, 0.1, 1.05
      animation=windows, 1, 7, windowBezier
      animation=windowsOut, 1, 7, default, popin 80%
      animation=border, 1, 10, default
      animation=borderangle, 1, 8, default
      animation=fade, 1, 7, default
      animation=workspaces, 1, 6, default
      enabled=yes
    }
  '';
in {
  # puts systemd init logs on tty1
  # so that tuigreet and systemd logs don't clobber each other
  boot.kernelParams = [
    "console=tty1"
  ];
  programs.regreet = {
    enable = false;
    settings = {
      background.path = ../../hm_modules/gui/wallpapers/1.jpg;
      background.fit = "Fill";
      GTK.application_prefer_dark_theme = true;
      commands.reboot = ["systemctl" "reboot"];
      commands.poweroff = ["systemctl" "poweroff"];
    };
  };
  services.greetd = {
    vt = 2; # on tty 2 cause systemd logs are on tty 1
    enable = true;
    settings.default_session.command = "${pkgs.dbus}/bin/dbus-run-session ${lib.getExe pkgs.hyprland} --config ${hyprlandGreetConfig}";
  };
  environment.etc."greetd/environments".text = ''
    Hyprland
    sway
    zsh
    bash
  '';
}
