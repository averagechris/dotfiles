# wlogout power menu with Rose Pine Moon theme
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.wlogout;
in {
  options.dotfiles.wlogout = {
    enable = lib.mkEnableOption "wlogout power menu";
  };

  config = lib.mkIf cfg.enable {
    programs.wlogout = {
      enable = true;
      layout = [
        {
          label = "lock";
          action = "hyprlock";
          text = "Lock";
          keybind = "l";
        }
        {
          label = "logout";
          action = "hyprctl dispatch exit";
          text = "Logout";
          keybind = "e";
        }
        {
          label = "suspend";
          action = "systemctl suspend";
          text = "Suspend";
          keybind = "s";
        }
        {
          label = "reboot";
          action = "systemctl reboot";
          text = "Reboot";
          keybind = "r";
        }
        {
          label = "shutdown";
          action = "systemctl poweroff";
          text = "Shutdown";
          keybind = "p";
        }
      ];

      style = ''
        /* Rose Pine Moon theme for wlogout */
        @define-color base #232136;
        @define-color surface #2a273f;
        @define-color overlay #393552;
        @define-color text #e0def4;
        @define-color love #eb6f92;
        @define-color gold #f6c177;
        @define-color iris #c4a7e7;
        @define-color foam #9ccfd8;

        * {
          font-family: "Inter", sans-serif;
          font-size: 14px;
        }

        window {
          background-color: rgba(35, 33, 54, 0.9);
        }

        button {
          background-color: @surface;
          border: 2px solid @overlay;
          border-radius: 12px;
          margin: 10px;
          color: @text;
          background-repeat: no-repeat;
          background-position: center;
          background-size: 25%;
        }

        button:hover {
          background-color: @overlay;
          border-color: @iris;
        }

        button:focus {
          background-color: @iris;
          color: @base;
        }

        #lock {
          background-image: image(url("${pkgs.wlogout}/share/wlogout/icons/lock.png"));
        }

        #logout {
          background-image: image(url("${pkgs.wlogout}/share/wlogout/icons/logout.png"));
        }

        #suspend {
          background-image: image(url("${pkgs.wlogout}/share/wlogout/icons/suspend.png"));
        }

        #reboot {
          background-image: image(url("${pkgs.wlogout}/share/wlogout/icons/reboot.png"));
        }

        #shutdown {
          background-image: image(url("${pkgs.wlogout}/share/wlogout/icons/shutdown.png"));
        }
      '';
    };
  };
}
