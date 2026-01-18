{
  pkgs,
  lib,
  config,
  ...
}: let
  displayLock = "${pkgs.swaylock-effects}/bin/swaylock -f -c 000000";
  cfg = config.dotfiles.gui.swayidle;
in {
  options.dotfiles.gui.swayidle.enable = lib.mkEnableOption "Enable swayidle, configured to work with hyprland or sway.";

  config = lib.mkIf cfg.enable {
    systemd.user.services.swayidle = {
      Unit = {
        Description = "Sway Idle Manager";
        Documentation = "man:swayidle(1)";
        PartOf = ["graphical-session.target"];
      };

      Install = {WantedBy = ["graphical-session.target"];};

      Service = {
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
