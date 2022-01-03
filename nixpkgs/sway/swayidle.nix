{ config, pkgs, ... }:
let
  displayOn = ''${pkgs.sway}/bin/swaymsg "output * dpms on"'';
  displayOff = ''${pkgs.sway}/bin/swaymsg "output * dpms off"'';
  displayLock = "swaylock -f -c 000000";
in
{
  config.systemd.user.services.swayidle = {
    Unit = {
      Description = "Sway Idle Manager";
      Documentation = "man:swayidle(1)";
      PartOf = [ "graphical-session.target" ];
    };

    Install = { WantedBy = [ "graphical-session.target" ]; };

    Service = {
      ExecStart = ''
        ${pkgs.swayidle}/bin/swayidle -w \
          timeout 120 '${displayOff}' \
          resume '${displayOn}' \
          timeout 130 '${displayLock}' \
          resume 'swaymsg "${displayOn}"' \
          timeout 300 'systemctl suspend'\
          resume 'swaymsg "${displayOn}"' \
          before-sleep '${displayLock}'
      '';
    };
  };
}
