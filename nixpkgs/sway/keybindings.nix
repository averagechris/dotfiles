{ config, pkgs, ... }:
let
  cfg = config.wayland.windowManager.sway.config;
  nwg-drawer = (pkgs.callPackage ./tmp_nwg-drawer.nix { });
  nwg-bar = (pkgs.callPackage ./nwg-bar.nix { });
  pactl = "${pkgs.pulseaudio}/bin/pactl";
  execNwgBar = "exec ${nwg-bar}/bin/nwg-bar";
  execPlayerctl = "exec ${pkgs.playerctl}/bin/playerctl";
  brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
  j4-dmenu-desktop = pkgs.j4-dmenu-desktop.overrideAttrs (old: {
    postPatch = ''
      sed -e 's,dmenu -i,${pkgs.bemenu}/bin/bemenu -i -b -f -l 5,g' -i ./src/Main.hh
    '';
  });
  leaveModeKeys = {
    "Insert" = "mode default";
    "Escape" = "mode default";
    "Return" = "mode default";
  };
  setVolume = "exec ${pactl} set-sink-volume $(${pactl} list short sinks | grep RUNNING | cut -f 1)";

in
{
  config.wayland.windowManager.sway.config.modes = {
    disabled_mode = {
      # a mode for ignoring all keybindings until the compose mode keys are
      # repeated.
      "Shift+space" = "mode default";
    };
    compose_mode = {
      # a mode for entering other modes, or inserting commands based on
      # sequential key presses
      # e.g. Shift+space -> k -> s  == bemenu_try_restart_systemd_user_services
      f = "fullscreen toggle; mode default;";
      k = "mode kill_mode";
      r = "mode resize_mode";
      t = ''exec swaymsg [app_id="scratch_terminal"] scratchpad show; mode default;'';
      v = "mode volume_mode";
      "Shift+space" = "mode disabled_mode";
    } // leaveModeKeys;
    kill_mode = {
      "Shift+q" = "exec swaymsg exit";
      q = "${execNwgBar}";
      r = "exec systemctl reboot -i";
      s = "exec bemenu_try_restart_systemd_user_services; mode default;";
      w = "kill; mode default;";
    } // leaveModeKeys;
    resize_mode = {
      "${cfg.up}" = "resize shrink width 15 px";
      "${cfg.down}" = "resize grow height 15 px";
      "${cfg.left}" = "resize shrink height 15 px";
      "${cfg.right}" = "resize grow width 15 px";
      "Shift+${cfg.up}" = "resize shrink width 45 px";
      "Shift+${cfg.down}" = "resize grow height 45 px";
      "Shift+${cfg.left}" = "resize shrink height 45 px";
      "Shift+${cfg.right}" = "resize grow width 45 px";
    } // leaveModeKeys;
    volume_mode = {
      "${cfg.up}" = "${setVolume} +1%";
      "Shift+${cfg.up}" = "${setVolume} +10%";
      "${cfg.down}" = "${setVolume} -1%";
      "Shift+${cfg.down}" = "${setVolume} -10%";
    } // leaveModeKeys;
    workspace_mode = {
      "0" = "workspace 0";
      "1" = "workspace 1";
      "2" = "workspace 2";
      "3" = "workspace 3";
      "4" = "workspace 4";
      "5" = "workspace 5";
      "6" = "workspace 6";
      "7" = "workspace 7";
      "8" = "workspace 8";
      "9" = "workspace 9";
      "${cfg.right}" = "workspace next";
      "${cfg.left}" = "workspace prev";
    } // leaveModeKeys;
  };

  config.wayland.windowManager.sway.config.keybindings = {
    "${cfg.modifier}+t" = "exec ${cfg.terminal}";
    "${cfg.modifier}+q" = "kill";
    "${cfg.modifier}+space" = ''exec ${j4-dmenu-desktop}/bin/j4-dmenu-desktop'';
    "${cfg.modifier}+Shift+q" = "${execNwgBar}";

    XF86LaunchB = "exec ${nwg-drawer}/bin/nwg-drawer";
    XF86AudioPlay = "${execPlayerctl} play-pause";
    XF86AudioNext = "${execPlayerctl} next";
    XF86AudioPrev = "${execPlayerctl} previous";
    XF86AudioLowerVolume = "${setVolume} -5%";
    XF86AudioRaiseVolume = "${setVolume} +5%";
    XF86AudioMute = "${setVolume} 0%";
    XF86MonBrightnessDown = "exec ${brightnessctl} set 5%-";
    XF86MonBrightnessUp = "exec ${brightnessctl} set +5%";

    # take a screenshot
    "${cfg.modifier}+ctrl+5" = ''exec grim -g "$(slurp)" - | swappy -f -'';

    "${cfg.modifier}+${cfg.left}" = "focus left";
    "${cfg.modifier}+${cfg.down}" = "focus down";
    "${cfg.modifier}+${cfg.up}" = "focus up";
    "${cfg.modifier}+${cfg.right}" = "focus right";

    "${cfg.modifier}+Shift+${cfg.left}" = "move left";
    "${cfg.modifier}+Shift+${cfg.down}" = "move down";
    "${cfg.modifier}+Shift+${cfg.up}" = "move up";
    "${cfg.modifier}+Shift+${cfg.right}" = "move right";

    "${cfg.modifier}+f" = "fullscreen toggle";

    "${cfg.modifier}+ctrl+s" = "layout stacking";
    "${cfg.modifier}+ctrl+w" = "layout tabbed";
    "${cfg.modifier}+ctrl+e" = "layout toggle split";

    "${cfg.modifier}+Shift+f" = "floating toggle";
    "${cfg.modifier}+Shift+s" = "sticky toggle";

    "${cfg.modifier}+1" = "workspace number 1";
    "${cfg.modifier}+2" = "workspace number 2";
    "${cfg.modifier}+3" = "workspace number 3";
    "${cfg.modifier}+4" = "workspace number 4";
    "${cfg.modifier}+5" = "workspace number 5";
    "${cfg.modifier}+6" = "workspace number 6";
    "${cfg.modifier}+7" = "workspace number 7";
    "${cfg.modifier}+8" = "workspace number 8";
    "${cfg.modifier}+9" = "workspace number 9";
    "${cfg.modifier}+ctrl+${cfg.right}" = "workspace next";
    "${cfg.modifier}+ctrl+${cfg.left}" = "workspace prev";
    "${cfg.modifier}+ctrl+${cfg.down}" = "workspace back_and_forth";
    "${cfg.modifier}+ctrl+${cfg.up}" = "workspace back_and_forth";

    "${cfg.modifier}+Shift+1" = "move container to workspace number 1";
    "${cfg.modifier}+Shift+2" = "move container to workspace number 2";
    "${cfg.modifier}+Shift+3" = "move container to workspace number 3";
    "${cfg.modifier}+Shift+4" = "move container to workspace number 4";
    "${cfg.modifier}+Shift+5" = "move container to workspace number 5";
    "${cfg.modifier}+Shift+6" = "move container to workspace number 6";
    "${cfg.modifier}+Shift+7" = "move container to workspace number 7";
    "${cfg.modifier}+Shift+8" = "move container to workspace number 8";
    "${cfg.modifier}+Shift+9" = "move container to workspace number 9";

    "${cfg.modifier}+Shift+minus" = "move scratchpad";
    "${cfg.modifier}+minus" = "scratchpad show";
    # NOTE: to remove a window from scratch pad toggle floating
    # https://i3wm.org/docs/userguide.html#_scratchpad

    "Shift+space" = "mode compose_mode";
  };

  config.home.packages = [
    nwg-drawer
    nwg-bar
  ];
}
