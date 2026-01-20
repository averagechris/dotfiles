# Hyprland Workstation Home Manager Module
#
# This module provides a unified configuration for Hyprland desktop hosts.
# It's the Hyprland equivalent of cosmic-workstation.nix, bundling all
# Hyprland desktop components and ecosystem tools.
#
# When enabled, it configures:
# - GUI environment with Hyprland window manager
# - Hyprland ecosystem tools (anyrun, swaync, hyprlock, hypridle, wlogout)
# - Theming and visual configuration
# - Shell utilities (yazi)
# - Terminal emulator selection (ghostty, kitty, wezterm, alacritty)
# - Common desktop utilities (clipboard, screenshots, media, audio)
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.dotfiles.hyprland-workstation;
in {
  options.dotfiles.hyprland-workstation = {
    enable = mkEnableOption "Hyprland workstation configuration";

    terminal = mkOption {
      type = types.enum ["ghostty" "kitty" "wezterm" "alacritty"];
      default = "ghostty";
      description = "Primary terminal emulator";
    };
  };

  config = mkIf cfg.enable {
    # Core GUI
    dotfiles.gui.enable = mkDefault true;
    dotfiles.gui.hyprland.enable = mkDefault true;

    # Hyprland ecosystem tools
    dotfiles.anyrun.enable = mkDefault true;
    dotfiles.swaync.enable = mkDefault true;
    dotfiles.hyprlock.enable = mkDefault true;
    dotfiles.hypridle.enable = mkDefault true;
    dotfiles.wlogout.enable = mkDefault true;
    dotfiles.theming.enable = mkDefault true;
    dotfiles.eww.enable = mkDefault true;

    # Shell utilities
    dotfiles.shell.yazi.enable = mkDefault true;

    # Terminal selection
    dotfiles.ghostty.enable = mkIf (cfg.terminal == "ghostty") (mkDefault true);
    dotfiles.ghostty.service.enable = mkIf (cfg.terminal == "ghostty") (mkDefault true);
    programs.kitty.enable = mkIf (cfg.terminal == "kitty") (mkDefault true);
    dotfiles.wezterm.enable = mkIf (cfg.terminal == "wezterm") (mkDefault true);
    programs.alacritty.enable = mkIf (cfg.terminal == "alacritty") (mkDefault true);

    # Common packages for Hyprland desktop
    home.packages = with pkgs; [
      # Clipboard
      wl-clipboard
      cliphist

      # Screenshots
      grimblast
      wf-recorder # Screen recording

      # Media
      imv # Image viewer
      mpv # Video player
      playerctl # Media controls
      zathura # PDF viewer

      # Audio
      pavucontrol
      pamixer

      # Utilities
      libnotify
      brightnessctl
      qalculate-gtk # Calculator

      # File management
      nautilus
      file-roller # Archive manager

      # System monitoring
      btop
      duf # Disk usage
      ncdu # NCurses disk usage

      # Hypr ecosystem tools
      hyprpicker
      hyprsunset
      hyprsysteminfo

      # Networking
      networkmanagerapplet
    ];

    # SSH agent
    services.ssh-agent.enable = lib.mkDefault true;
  };
}
