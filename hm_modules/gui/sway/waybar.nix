{
  pkgs,
  lib,
  config,
  ...
}: {
  config = lib.mkIf config.dotfiles.gui.enable {
    programs.waybar = {
      systemd = {
        enable = false;
        target = "sway-session.target";
      };
      style = builtins.readFile ./waybar_style.css;
      settings = [
        {
          layer = "top";
          position = "top";
          height = 24;
          modules-left = ["clock" "custom/media"];
          modules-center = ["sway/mode" "sway/workspaces"];
          modules-right = ["idle_inhibitor" "pulseaudio" "network" "bluetooth" "battery" "tray"];
          "sway/workspaces" = {
            disable-scroll = true;
            all-outputs = false;
            format = "{icon}";
            format-icons = {
              urgent = "🔥";
              focused = "";
              default = "";
            };

            # "sway/mode".format = "<span style=\"italic\">{}</span>";

            clock = {
              format = "{:%I:%M %p}";
              format-alt = "{:%Y-%m-%d}";
            };
            battery = {
              bat = "BAT0";
              states = {
                good = 95;
                warning = 25;
                critical = 10;
              };
              format = "{icon}";
              format-icons = ["" "" "" "" ""];
              tooltip-format = ''
                {capacity}%
                {timeTo}
              '';
            };
            network = {
              # interface = "wlp2s0";  # (Optional) To force the use of this interface
              format-wifi = "";
              format-ethernet = "";
              format-disconnected = "⚠";
              tooltip-format-wifi = "{essid} ({signalStrength}%) ";
              tooltip-format-ethernet = "ethernet: {ifname}: {ipaddr}/{cidr}";
              tooltip-format-disconnected = "Disconnected";
            };
            pulseaudio = {
              format = "{volume}% {icon}";
              format-bluetooth = "{volume}% {icon}";
              format-muted = "";
              format-icons = {
                headphones = "";
                handsfree = "";
                headset = "";
                phone = "";
                portable = "";
                car = "";
                default = ["" ""];
              };
              on-click = "${pkgs.pavucontrol}/bin/pavucontrol";
            };
            idle_inhibitor = {
              format = "{icon}";
              format-icons = {
                activated = "";
                deactivated = "";
              };
            };
            "custom/media" = {
              on-click = "${pkgs.playerctl}/bin/playerctl play-pause";
              format = "🎵 {}";
              max-length = 40;
              interval = 30; # Remove this if your script is endless and write in loop
              exec = with pkgs; let
                name = "waybar_media_play_pause_toggler";
              in "${writeShellApplication {
                inherit name;
                runtimeInputs = [playerctl];
                text = ''
                  player_status=$(playerctl status 2>/dev/null)

                  if [ "$player_status" = "Playing" ]; then
                    echo "$(playerctl metadata artist) - $(playerctl metadata title)"

                  elif [ "$player_status" = "Paused" ]; then
                    echo " $(playerctl metadata artist) - $(playerctl metadata title)"

                  else
                    echo "$(playerctl status): $(playerctl metadata title)"

                  fi
                '';
              }}/bin/${name}";
            };

            tray = {
              icon-size = 21;
              spacing = 10;
            };
          };
        }
      ];
    };
  };
}
