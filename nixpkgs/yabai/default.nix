#########################################
# yabai is a macos tiling window manager
# https://github.com/koekeishiya/yabai
#########################################

{ pkgs, lib, ... }:

let

  utils = import ../utils pkgs;

  yabai = {
    config = {
      window_placement = "second_child";
      window_topmost = true;
      window_shadow = "float";
      window_border = false;
      window_opacity = false;
      insert_feedback_color = "0xffd75f5f";
      split_ratio = "0.50";
      auto_balance = true;
      mouse_drop_action = "swap";
      layout = "bsp";
      top_padding = 6;
      bottom_padding = 6;
      left_padding = 6;
      right_padding = 6;
      window_gap = 6;
    };
    managed_apps = {
      # apps are usually managed by default
      "System Information" = false;
      "System Preferences" = false;
      "Karabiner-Elements" = false;
      "Disk Utility" = false;
      "Flux" = false;
      "Messages" = false;
      "sure-zooms" = false;
    };
  };

  yabaiify = utils.stringify {
    mkKey = k: "yabai -m config ${k}";
    mkValue = v:
      if lib.isBool v then (if v then "on" else "off")
      else lib.generators.mkValueStringDefault { } v;
  };

  yabaiifyRules = utils.stringify {
    mkKey = k: "yabai -m rule --add app='^${k}$'";
    mkValue = v: "manage=${if v then "on" else "off"}";
  };

in
{
  home.packages = [ pkgs.yabai ];

  xdg.configFile."yabai/yabairc".text = ''
    #!/usr/bin/env sh

    #############################################################
    # Generated by home-manager from nixpkgs.yabai in ~/dotfiles
    # For yabai info see: https://github.com/koekeishiya/yabai
    #############################################################

    ${yabaiify yabai.config}

    ${yabaiifyRules yabai.managed_apps}

    # float iterm window that emulate guake (floats from bottom)
    yabai -m rule --add app='^iTerm2$' title="^Hotkey Window$" manage=off

    echo "$(date "+%Y-%m-%d %H:%M:%s") - yabai configuration loaded..."
  '';
}
