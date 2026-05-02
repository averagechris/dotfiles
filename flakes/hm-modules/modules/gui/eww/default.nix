# Eww bar and widgets configuration
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.eww;

  # Rose Pine Moon colors
  colors = {
    base = "#232136";
    surface = "#2a273f";
    overlay = "#393552";
    muted = "#6e6a86";
    subtle = "#908caa";
    text = "#e0def4";
    love = "#eb6f92";
    gold = "#f6c177";
    rose = "#ea9a97";
    pine = "#3e8fb0";
    foam = "#9ccfd8";
    iris = "#c4a7e7";
    highlightLow = "#2a283e";
    highlightMed = "#44415a";
    highlightHigh = "#56526e";
  };
  ewwOpenBars = pkgs.writeShellApplication {
    name = "eww-open-bars";
    runtimeInputs = [pkgs.eww pkgs.hyprland pkgs.jq];
    text = ''
      set -euo pipefail

      eww daemon || true
      sleep 0.2

      if hyprctl monitors -j | jq -e '.[] | select(.name == "eDP-1")' >/dev/null; then
        eww open bar-internal || true
      else
        eww close bar-internal || true
      fi

      if hyprctl monitors -j | jq -e '.[] | select(.name == "DP-2")' >/dev/null; then
        eww open bar-external || true
      else
        eww close bar-external || true
      fi
    '';
  };
in {
  options.dotfiles.eww = {
    enable = lib.mkEnableOption "Eww bar and widgets";
  };

  config = lib.mkIf cfg.enable {
    programs.eww = {
      enable = true;
      package = pkgs.eww;
      configDir = ./config;
    };

    # Scripts for eww widgets
    home.packages = with pkgs; [
      jq
      socat
      playerctl
      pamixer
      brightnessctl
      networkmanager
      networkmanagerapplet # provides nm-connection-editor
      bluez
      overskride # Bluetooth GUI
      ewwOpenBars
    ];

    # Ensure eww starts with Hyprland
    wayland.windowManager.hyprland.settings.exec-once = lib.mkIf config.dotfiles.gui.hyprland.enable [
      "eww daemon"
      "eww-open-bars"
    ];
  };
}
