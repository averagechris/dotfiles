{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf config.dotfiles.gui.sway.enable {
    wayland.windowManager.sway = {
      config.fonts.names = ["DejaVu Sans Mono" "FontAwesome5Free"]; # TODO don't hardcode
      config.bars = [{command = "waybar";}];
      config.floating.criteria = [
        {app_id = "pavucontrol";}
        {app_id = "zenity";}
        {
          app_id = "org.keepassxc.KeePassXC";
        }
        {class = ".zoom";}
      ];
      config.floating.titlebar = false;
      config.focus.mouseWarping = true;
      config.gaps.inner = 3;
      config.gaps.outer = 3;
      config.gaps.smartGaps = true;
      config.input."*".natural_scroll = "enabled";
      config.input."type:touchpad" = {
        tap = lib.mkDefault "enabled";
        tap_button_map = lib.mkDefault "lrm";
        accel_profile = lib.mkDefault "adaptive";
      };
      config.output."*".bg = "${../wallpapers}/1.jpg fill";
      config.startup = [
        {
          command = "${pkgs.kanshi}/bin/kanshi";
          always = true;
        }
      ];
      config.window.titlebar = false;
      config.workspaceAutoBackAndForth = true;
      wrapperFeatures.base = true;
      wrapperFeatures.gtk = true;
      extraConfig = ''
        seat seat0 xcursor_theme breeze 62
        for_window [app_id="scratch_terminal"] move scratchpad, resize set 800 610
        exec ${pkgs.alacritty}/bin/alacritty --title=scratch_terminal
      '';
    };
  };
}
