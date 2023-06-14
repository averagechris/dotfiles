{
  config,
  pkgs,
  lib,
  dotfiles_lib,
  ...
}: let
  cfg = config.programs.meganz;
in
  with lib; {
    options.programs.meganz = with dotfiles_lib.options; {
      enable = mkEnableOption "Install meganz and optionally the configured gui app + systemd sync service.";
      sync.enable = mkDefaultEnabledOption "Enable a systemd service to start mega's sync in the background to initiate syncing any configured sync folders.";
      gui.enable = mkEnableOption "Install the gui mega app called MegaSync.";
    };
    config = mkIf cfg.enable {
      home.packages =
        [pkgs.megacmd]
        ++ (
          if config.programs.meganz.gui.enable
          then [pkgs.megasync]
          else []
        );

      systemd.user.services.mega-cmd-server-init = {
        Unit.Description = "Try to start mega-cmd when sway starts.";
        Install.WantedBy = ["graphical-session.target"];
        Service.Type = "oneshot";
        Service.ExecStart = "${pkgs.megacmd}/bin/mega-cmd-server";
      };
    };
  }
