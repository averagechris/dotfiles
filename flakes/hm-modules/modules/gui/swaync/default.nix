# Swaync notification center with Rose Pine Moon theme
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.swaync;
in {
  options.dotfiles.swaync = {
    enable = lib.mkEnableOption "Swaync notification center";
  };

  config = lib.mkIf cfg.enable {
    services.swaync = {
      enable = true;
      settings = {
        positionX = "right";
        positionY = "top";
        layer = "overlay";
        control-center-layer = "top";
        layer-shell = true;
        cssPriority = "application";
        control-center-margin-top = 10;
        control-center-margin-bottom = 10;
        control-center-margin-right = 10;
        notification-icon-size = 64;
        notification-body-image-height = 100;
        notification-body-image-width = 200;
        timeout = 5;
        timeout-low = 3;
        timeout-critical = 0;
        fit-to-screen = true;
        control-center-width = 400;
        notification-window-width = 400;
        keyboard-shortcuts = true;
        image-visibility = "when-available";
        transition-time = 200;
        hide-on-clear = true;
        hide-on-action = true;
        script-fail-notify = true;
        widgets = [
          "inhibitors"
          "title"
          "dnd"
          "notifications"
        ];
        widget-config = {
          inhibitors = {
            text = "Inhibitors";
            button-text = "Clear";
            clear-all-button = true;
          };
          title = {
            text = "Notifications";
            clear-all-button = true;
            button-text = "Clear All";
          };
          dnd = {
            text = "Do Not Disturb";
          };
        };
      };

      style = ''
        /* Rose Pine Moon theme for Swaync */
        @define-color base #232136;
        @define-color surface #2a273f;
        @define-color overlay #393552;
        @define-color muted #6e6a86;
        @define-color subtle #908caa;
        @define-color text #e0def4;
        @define-color love #eb6f92;
        @define-color gold #f6c177;
        @define-color rose #ea9a97;
        @define-color pine #3e8fb0;
        @define-color foam #9ccfd8;
        @define-color iris #c4a7e7;

        * {
          font-family: "Inter", sans-serif;
          font-size: 14px;
        }

        .control-center {
          background: @base;
          border: 2px solid @overlay;
          border-radius: 12px;
        }

        .notification {
          background: @surface;
          border-radius: 8px;
          margin: 4px 8px;
          padding: 8px;
        }

        .notification-content {
          color: @text;
        }

        .notification-default-action {
          border-radius: 8px;
        }

        .notification-default-action:hover {
          background: @overlay;
        }

        .close-button {
          background: @overlay;
          color: @text;
          border-radius: 6px;
          padding: 4px 8px;
        }

        .close-button:hover {
          background: @love;
          color: @base;
        }

        .widget-title {
          color: @text;
          font-weight: bold;
          padding: 8px;
        }

        .widget-title button {
          background: @overlay;
          color: @text;
          border-radius: 6px;
          padding: 4px 12px;
        }

        .widget-title button:hover {
          background: @iris;
          color: @base;
        }

        .widget-dnd {
          background: @surface;
          border-radius: 8px;
          margin: 4px 8px;
          padding: 8px;
        }

        .widget-dnd > switch {
          background: @overlay;
          border-radius: 12px;
        }

        .widget-dnd > switch:checked {
          background: @iris;
        }

        .widget-dnd > switch slider {
          background: @text;
          border-radius: 10px;
        }
      '';
    };
  };
}
