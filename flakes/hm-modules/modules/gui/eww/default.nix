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
