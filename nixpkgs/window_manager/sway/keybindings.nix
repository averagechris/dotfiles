{ config, pkgs, ...}:
let
  cfg = config.wayland.windowManager.sway.config;
  modkey = cfg.modifier;
  nwg-drawer = (pkgs.callPackage ./tmp_nwg-drawer.nix {});
  nwg-bar = (pkgs.callPackage ./nwg-bar.nix {});

in
{
  config.wayland.windowManager.sway.config.keybindings = {
    "${modkey}+t" = "exec ${cfg.terminal}";
    "${modkey}+q" = "kill";
    "${modkey}+space" = "exec ${pkgs.nwg-launchers}/bin/nwgdmenu";
    "XF86LaunchB" = "exec ${nwg-drawer}/bin/nwg-drawer";
    "${modkey}+Shift+q" = "exec ${nwg-bar}/bin/nwg-bar";

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

    "${modkey}+b" = "splith";
    "${modkey}+v" = "splitv";
    "${modkey}+f" = "fullscreen toggle";
    "${modkey}+a" = "focus parent";

    "${modkey}+ctrl+s" = "layout stacking";
    "${modkey}+ctrl+w" = "layout tabbed";
    "${modkey}+ctrl+e" = "layout toggle split";

    "${modkey}+Shift+space" = "floating toggle";
    # "${modkey}+space" = "focus mode_toggle";
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
    "${modkey}+ctrl+l" = "workspace next";
    "${modkey}+ctrl+h" = "workspace prev";
    "${modkey}+ctrl+p" = "workspace back_and_forth";

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

    "${modkey}+Shift+c" = "reload";

    "${modkey}+r" = "mode resize";
  };

  config.home.packages = [ nwg-drawer nwg-bar pkgs.nwg-launchers ];
}
