#########################################
# yabai is a macos tiling window manager
# https://github.com/koekeishiya/yabai
#########################################

{ config, pkgs, ...}:

let
  utils = (import ../utils pkgs);
  yabaiifyRules = utils.stringify {
    mkKey = k: "yabai -m rule --add app='^${k}$'";
    mkValue = v: "manage=${if v then "on" else "off"}";
  };

  unmanaged_apps = {
    # apps are usually managed by default
    "System Information" = false;
    "System Preferences" = false;
    "Karabiner-Elements" = false;
    "Disk Utility" = false;
    "Flux" = false;
    "Messages" = false;
    "sure-zooms" = false;
  };

in {
  config.services.yabai = {
    enable = true;
    package = pkgs.yabai;
    config = {
      window_placement = "second_child";
      window_topmost = "on";
      window_shadow = "float";
      window_border = "off";
      window_opacity = "off";
      insert_feedback_color = "0xffd75f5f";
      split_ratio = "0.50";
      auto_balance = "on";
      mouse_drop_action = "swap";
      layout = "bsp";
      top_padding = 6;
      bottom_padding = 6;
      left_padding = 6;
      right_padding = 6;
      window_gap = 6;
    };
    extraConfig = ''
      ${yabaiifyRules unmanaged_apps}

      # float iterm window that emulate guake (floats from bottom)
      yabai -m rule --add app='^iTerm2$' title="^Hotkey Window$" manage=off

      echo "$(date "+%Y-%m-%d %H:%M:%s") - yabai configuration loaded..."
    '';
  };
}
