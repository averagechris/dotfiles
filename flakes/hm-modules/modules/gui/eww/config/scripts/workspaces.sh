#!/usr/bin/env bash
# Get Hyprland workspaces

workspaces() {
  hyprctl workspaces -j | jq -c '[.[].id] | sort | .[]' | tr '\n' ' ' | sed 's/ $//'
}

# Initial output
echo "[$(workspaces)]"

# Listen for workspace changes
socat -u UNIX-CONNECT:/tmp/hypr/"$HYPRLAND_INSTANCE_SIGNATURE"/.socket2.sock - | while read -r line; do
  case $line in
    workspace*|createworkspace*|destroyworkspace*)
      echo "[$(workspaces)]"
      ;;
  esac
done
