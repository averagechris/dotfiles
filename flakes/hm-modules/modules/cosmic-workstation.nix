# COSMIC Workstation Home Manager Module
#
# This module provides a unified configuration for COSMIC desktop hosts (trap, thorny, cruber).
# It extracts common home-manager settings used across these systems and provides
# optional features like ghostty terminal and helix-terminal-tools integration.
#
# When enabled, it configures:
# - GUI environment with wezterm as the default terminal
# - Shell utilities (calibre-utils, python, pipx, yazi)
# - Helix editor with wezterm terminal flavor
# - COSMIC-specific portal workarounds
# - Optional ghostty terminal emulator
# - Optional helix-terminal-tools with yazi integration
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.dotfiles.cosmic-workstation;
in {
  options.dotfiles.cosmic-workstation = {
    enable = mkEnableOption "COSMIC workstation configuration for home-manager";

    ghostty = {
      enable = mkEnableOption "Ghostty terminal emulator (default: false)";
    };

    helix-terminal-tools = {
      enable = mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable helix-terminal-tools with yazi integration";
      };
    };
  };

  config = mkIf cfg.enable {
    # Core GUI configuration
    dotfiles.gui.enable = mkDefault true;
    dotfiles.gui.hyprland.enable = mkDefault false;

    # Shell utilities
    dotfiles.shell.calibre-utils.enable = mkDefault true;
    dotfiles.shell.python.enable = mkDefault true;
    dotfiles.shell.pipx.enable = mkDefault true;
    dotfiles.shell.yazi.enable = mkDefault true;

    # Terminal and editor configuration
    dotfiles.wezterm.enable = mkDefault true;
    programs.helix.terminal.flavor = mkDefault "wezterm";

    # Disable waybar (COSMIC has its own panel)
    programs.waybar.enable = mkDefault false;

    # Enable COSMIC-specific portal workarounds
    dotfiles.gui.cosmic-portal-workarounds.enable = mkDefault true;

    # Optional ghostty terminal emulator
    dotfiles.ghostty.enable = mkIf cfg.ghostty.enable true;
    dotfiles.ghostty.service.enable = mkIf cfg.ghostty.enable true;

    # Optional helix-terminal-tools with yazi integration
    dotfiles.helix-terminal-tools = mkIf cfg.helix-terminal-tools.enable {
      enable = true;
      yazi = {
        enable = true;
        pickerWidth = 30;
        pickerSide = "left";
        helixKeybinding = "space.t.f";
      };
    };
  };
}
