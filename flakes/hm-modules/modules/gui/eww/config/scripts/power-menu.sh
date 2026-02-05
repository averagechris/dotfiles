#!/usr/bin/env bash

# Power menu wrapper for wlogout
# This ensures wlogout runs properly and stays open

# Kill any existing wlogout instances first
pkill -f wlogout

# Launch wlogout with layer-shell protocol for Wayland
wlogout --protocol layer-shell

# Alternative fallback if wlogout fails
if [ $? -ne 0 ]; then
    # Use wofi as fallback
    choice=$(echo -e "Lock\nLogout\nSuspend\nReboot\nShutdown" | wofi --show dmenu --prompt "Power Menu")
    case "$choice" in
        "Lock") hyprlock ;; 
        "Logout") hyprctl dispatch exit ;; 
        "Suspend") systemctl suspend ;; 
        "Reboot") systemctl reboot ;; 
        "Shutdown") systemctl poweroff ;; 
    esac
fi