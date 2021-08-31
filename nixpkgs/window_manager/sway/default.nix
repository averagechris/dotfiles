{ config, pkgs, lib, ... }:

let
  cfg = config.wayland.windowManager.sway.config;
  modkey = cfg.modifier;

in {

  config.wayland.windowManager.sway = {
    enable = true;
    config.bars = [];
    config.floating.criteria = [ { class = "Pavucontrol"; } ];
    config.floating.titlebar = true;
    config.gaps.inner = 3;
    config.gaps.outer = 3;
    config.gaps.smartGaps = true;
    config.input."*".natural_scroll = "enabled";
    config.input."touchpad".tap = "enabled";
    config.keybindings = import ./keybindings.nix { modkey = modkey; cfg = cfg; };
    config.workspaceAutoBackAndForth = true;
    wrapperFeatures.base = true;
    wrapperFeatures.gtk = true;
    extraSessionCommands = ''
      export MOZ_ENABLE_WAYLAND=1
    '';
  };

  config.programs.waybar = import ./waybar.nix { pkgs = pkgs; };

  # notifications daemon
  config.programs.mako = {
    enable = true;
    anchor = "top-center";
    defaultTimeout = 1750;
  };

  config.xdg.configFile."swappy/config".text = ''
    [Default]
    save_dir=$HOME/screenshots
    save_filename_format=%Y%m%d-%H%M%S-screenshot.png
    show_panel=false
    line_size=5
    text_size=20
    text_font=sans-serif
  '';

  config.home.packages = with pkgs; [
    source-code-pro
    libnotify
    mpv
    imv
    pavucontrol
    playerctl
    wl-clipboard

    #####################
    # screenshot utiities
    #####################
    grim
    slurp
    swappy
  ];
}
