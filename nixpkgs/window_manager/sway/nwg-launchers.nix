{ config, pkgs, ... }:

{
  config.xdg.configFile."nwg-launchers/nwgbar/icons".source = ./icons;

  config.xdg.configFile."nwg-launchers/nwgbar/bar.json".text = ''
    [
      {
        "name": "Lock screen",
        "exec": "swaylock -f -c 000000",
        "icon": "${config.xdg.configHome}/nwg-luanchers/nwgbar/icons/system-lock-screen.svg"
      },
      {
        "name": "Logout",
        "exec": "swaynag -t warning -m 'close sway and wayland?' -b 'yes' 'swaymsg exit'",
        "icon": "${config.xdg.configHome}/nwg-luanchers/nwgbar/icons/system-log-out.svg"
      },
      {
        "name": "Reboot",
        "exec": "systemctl reboot",
        "icon": "${config.xdg.configHome}/nwg-luanchers/nwgbar/icons/system-reboot.svg"
      },
      {
        "name": "Shutdown",
        "exec": "systemctl -i poweroff",
        "icon": "${config.xdg.configHome}/nwg-luanchers/nwgbar/icons/system-shutdown.svg"
      }
    ]
  '';

  config.xdg.configFile."nwg-launchers/nwgbar/style.css".text = ''
    #bar {
        margin: 30px /* affects top/bottom & left/right alignment */
    }

    button, image {
        background: none;
        border-style: none;
        box-shadow: none;
        color: #999
    }

    button {
        padding-left: 10px;
        padding-right: 10px;
        margin: 5px
    }

    button:hover {
        background-color: rgba (255, 255, 255, 0.1)
    }

    button:focus {
        box-shadow: 0 0 2px;
    }

    grid {
        /* e.g. for common background to all buttons */
    }
  '';

  config.home.packages = with pkgs; [ nwg-launchers ];
}
