{pkgs, ...}: let
  # displayOn = ''${pkgs.sway}/bin/swaymsg "output * dpms on"'';
  # displayOff = ''${pkgs.sway}/bin/swaymsg "output * dpms off"'';
  displayLock = "${pkgs.swaylock-effects}/bin/swaylock -f -c 000000";
in {
  config = {
    systemd.user.services.swayidle = {
      Unit = {
        Description = "Sway Idle Manager";
        Documentation = "man:swayidle(1)";
        PartOf = ["graphical-session.target"];
      };

      Install = {WantedBy = ["graphical-session.target"];};

      Service = {
        # ExecStart = ''
        #   ${pkgs.swayidle}/bin/swayidle -w \
        #     timeout 240 '${displayOff}' \
        #     resume '${displayOn}' \
        #     timeout 180 '${displayLock}' \
        #     resume 'swaymsg "${displayOn}"' \
        #     timeout 1200 'systemctl suspend'\
        #     resume 'swaymsg "${displayOn}"' \
        #     before-sleep '${displayLock}'
        # '';
        ExecStart = ''
          ${pkgs.swayidle}/bin/swayidle -w \
            timeout 180 '${displayLock}' \
            timeout 1200 'systemctl suspend'\
            before-sleep '${displayLock}'
        '';
      };
    };
  };
}
