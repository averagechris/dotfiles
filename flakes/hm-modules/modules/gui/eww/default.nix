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
  eww = pkgs.writeShellApplication {
    name = "eww";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      set -euo pipefail

      # Eww derives its daemon socket from both XDG_RUNTIME_DIR and the
      # canonical config directory.  Some launch paths (for example commands
      # run outside the login shell's imported environment) can miss one of
      # these variables, which makes the CLI look for a different daemon than
      # the Hyprland-started bar is using.
      export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
      export XDG_CONFIG_HOME="''${XDG_CONFIG_HOME:-$HOME/.config}"

      for arg in "$@"; do
        case "$arg" in
          -c|--config|--config=*)
            exec ${lib.getExe pkgs.eww} "$@"
            ;;
        esac
      done

      exec ${lib.getExe pkgs.eww} --config "$XDG_CONFIG_HOME/eww-stable" "$@"
    '';
  };
  ewwOpenBars = pkgs.writeShellApplication {
    name = "eww-open-bars";
    runtimeInputs = [eww pkgs.hyprland pkgs.jq];
    text = ''
      set -euo pipefail

      external_bar_for_monitor() {
        case "$1" in
          DP-1) printf '%s\n' bar-external-dp1 ;;
          DP-2) printf '%s\n' bar-external ;;
          DP-3) printf '%s\n' bar-external-dp3 ;;
          HDMI-A-1) printf '%s\n' bar-external-hdmi-a-1 ;;
          HDMI-A-2) printf '%s\n' bar-external-hdmi-a-2 ;;
          *) return 1 ;;
        esac
      }

      close_external_bars() {
        local keep="''${1:-}"
        for bar in bar-external-dp1 bar-external bar-external-dp3 bar-external-hdmi-a-1 bar-external-hdmi-a-2; do
          [[ "$bar" == "$keep" ]] && continue
          eww close "$bar" || true
        done
      }

      eww daemon || true
      sleep 0.2

      # Keep exactly one bar open. Prefer any enabled external display; otherwise
      # fall back to the laptop panel. USB-C docks can enumerate the same Dell as
      # DP-1/DP-2/DP-3 across boots, so do not hard-code only DP-2 here.
      external_monitor="$(hyprctl monitors -j | jq -r 'first(.[] | select(.name != "eDP-1" and (((.disabled // false) | not))) | .name) // empty')"
      if [[ -n "$external_monitor" ]] && external_bar="$(external_bar_for_monitor "$external_monitor")"; then
        eww open "$external_bar" || true
        eww close bar-internal || true
        close_external_bars "$external_bar"
      elif hyprctl monitors -j | jq -e '.[] | select(.name == "eDP-1" and (((.disabled // false) | not)))' >/dev/null; then
        eww open bar-internal || true
        close_external_bars
      else
        eww close bar-internal || true
        close_external_bars
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
      package = eww;
      configDir = ./config;
    };

    # Eww hashes the canonical config directory path into its daemon socket.
    # The default Home Manager configDir is a symlink to a generation-specific
    # store path, so the socket changes after every activation while the old
    # Hyprland-started daemon keeps running.  Keep the wrapper pointed at a
    # stable real directory with symlinked file contents instead.
    xdg.configFile = {
      "eww-stable/eww.yuck".source = ./config/eww.yuck;
      "eww-stable/eww.scss".source = ./config/eww.scss;
      "eww-stable/scripts" = {
        source = ./config/scripts;
        recursive = true;
      };
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
