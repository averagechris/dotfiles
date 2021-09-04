{ pkgs, ... }:
{
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    style = builtins.readFile ./waybar_style.css;
    settings = [
      {
        layer = "top";
        position = "top";
        height = 24;
        modules-left = [ "clock" "custom/media" ];
        modules-center = [ "sway/workspaces" ];
        modules-right = [ "pulseaudio" "network" "bluetooth" "cpu" "memory" "battery" ];
        modules = {
          "sway/workspaces" = {
            disable-scroll = true;
            all-outputs = false;
            format = "{icon}";
            format-icons = {
              urgent = "🔥";
              focused = "";
              default = "";
            };
          };

          # "sway/mode".format = "<span style=\"italic\">{}</span>";

          clock = {
            format = "{:%I:%M %p}";
            format-alt = "{:%Y-%m-%d}";
          };
          cpu.format = "ＣＰＵ{usage}%";
          memory.format = "ＭＥＭ{}%";
          battery = {
            bat = "BAT0";
            states = {
              good = 95;
              warning = 30;
              critical = 15;
            };
            format = "{icon}";
            format-icons = [ "" "" "" "" "" ];
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
              default = [ "" "" ];
            };
            on-click = "pavucontrol";
          };
          "custom/media" = {
            format = "🎵 {}";
            max-length = 40;
            interval = 30; # Remove this if your script is endless and write in loop
            exec = pkgs.writeShellScript "mediaplayer" (builtins.readFile ./playerctl.sh);
          };
        };
      }
    ];
  };
}
