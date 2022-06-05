{ config, pkgs, ... }:
let
  cfg = config.wayland.windowManager.sway.config;
  modkey = cfg.modifier;
  nwg-drawer = (pkgs.callPackage ./tmp_nwg-drawer.nix { });
  nwg-bar = (pkgs.callPackage ./nwg-bar.nix { });
  pactl = "${pkgs.pulseaudio}/bin/pactl";
  playerctl = "${pkgs.playerctl}/bin/playerctl";
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
      q = "exec swaymsg exit";
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
    "${modkey}+t" = "exec ${cfg.terminal}";
    "${modkey}+q" = "kill";
    "${modkey}+space" = ''exec ${j4-dmenu-desktop}/bin/j4-dmenu-desktop'';
    "${modkey}+Shift+q" = "exec ${nwg-bar}/bin/nwg-bar";

    XF86LaunchB = "exec ${nwg-drawer}/bin/nwg-drawer";
    XF86AudioPlay = "exec ${playerctl} play-pause";
    XF86AudioNext = "exec ${playerctl} next";
    XF86AudioPrev = "exec ${playerctl} previous";
    XF86AudioLowerVolume = "${setVolume} -5%";
    XF86AudioRaiseVolume = "${setVolume} +5%";
    XF86AudioMute = "${setVolume} 0%";
    XF86MonBrightnessDown = "exec ${brightnessctl} set 5%-";
    XF86MonBrightnessUp = "exec ${brightnessctl} set +5%";

    # take a screenshot
    "${modkey}+ctrl+5" = ''exec grim -g "$(slurp)" - | swappy -f -'';

    "${modkey}+${cfg.left}" = "focus left";
    "${modkey}+${cfg.down}" = "focus down";
    "${modkey}+${cfg.up}" = "focus up";
    "${modkey}+${cfg.right}" = "focus right";

    "${modkey}+Shift+${cfg.left}" = "move left";
    "${modkey}+Shift+${cfg.down}" = "move down";
    "${modkey}+Shift+${cfg.up}" = "move up";
    "${modkey}+Shift+${cfg.right}" = "move right";

    "${modkey}+f" = "fullscreen toggle";

    "${modkey}+ctrl+s" = "layout stacking";
    "${modkey}+ctrl+w" = "layout tabbed";
    "${modkey}+ctrl+e" = "layout toggle split";

    "${modkey}+Shift+f" = "floating toggle";
    "${modkey}+Shift+s" = "sticky toggle";

    "${modkey}+1" = "workspace number 1";
    "${modkey}+2" = "workspace number 2";
    "${modkey}+3" = "workspace number 3";
    "${modkey}+4" = "workspace number 4";
    "${modkey}+5" = "workspace number 5";
    "${modkey}+6" = "workspace number 6";
    "${modkey}+7" = "workspace number 7";
    "${modkey}+8" = "workspace number 8";
    "${modkey}+9" = "workspace number 9";
    "${modkey}+ctrl+${cfg.right}" = "workspace next";
    "${modkey}+ctrl+${cfg.left}" = "workspace prev";
    "${modkey}+ctrl+${cfg.down}" = "workspace back_and_forth";
    "${modkey}+ctrl+${cfg.up}" = "workspace back_and_forth";

    "${modkey}+Shift+1" = "move container to workspace number 1";
    "${modkey}+Shift+2" = "move container to workspace number 2";
    "${modkey}+Shift+3" = "move container to workspace number 3";
    "${modkey}+Shift+4" = "move container to workspace number 4";
    "${modkey}+Shift+5" = "move container to workspace number 5";
    "${modkey}+Shift+6" = "move container to workspace number 6";
    "${modkey}+Shift+7" = "move container to workspace number 7";
    "${modkey}+Shift+8" = "move container to workspace number 8";
    "${modkey}+Shift+9" = "move container to workspace number 9";

    "${modkey}+Shift+minus" = "move scratchpad";
    "${modkey}+minus" = "scratchpad show";
    # NOTE: to remove a window from scratch pad toggle floating
    # https://i3wm.org/docs/userguide.html#_scratchpad

    "Shift+space" = "mode compose_mode";
  };

  config.home.packages = [
    nwg-drawer
    nwg-bar
  ];
}
