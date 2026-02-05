#!/usr/bin/env bash
# Get active Hyprland workspace

# Initial output
echo "$(hyprctl activeworkspace -j | jq '.id')"

# Listen for workspace changes using correct socket path
socat -u UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/"$HYPRLAND_INSTANCE_SIGNATURE"/.socket2.sock - | while read -r line; do
  case $line in
    workspace*)
      echo "$(hyprctl activeworkspace -j | jq '.id')"
      ;;
  esac
done
