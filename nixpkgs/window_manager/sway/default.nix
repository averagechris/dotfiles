{ config, pkgs, lib, ... }:

let
  cfg = config.wayland.windowManager.sway.config;
  modkey = cfg.modifier;

in {
  imports = [
    ./nwg-launchers.nix
    ./screenshots.nix
    ./waybar.nix
  ];

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
    config.keybindings = import ./keybindings.nix { modkey = modkey; cfg = cfg; pkgs = pkgs; };
    config.workspaceAutoBackAndForth = true;
    wrapperFeatures.base = true;
    wrapperFeatures.gtk = true;
    extraSessionCommands = ''
      export MOZ_ENABLE_WAYLAND=1
    '';
  };

  # notifications daemon
  config.programs.mako = {
    enable = true;
    anchor = "top-center";
    defaultTimeout = 2750;
  };

  config.services.blueman-applet.enable = true;

  config.home.packages = with pkgs; [
    source-code-pro
    libnotify
    mpv
    imv
    pavucontrol
    playerctl
    wl-clipboard
  ];
}
