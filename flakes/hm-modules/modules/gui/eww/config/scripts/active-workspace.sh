#!/usr/bin/env bash
# Get active Hyprland workspace

# Initial output
hyprctl activeworkspace -j | jq '.id'

# Listen for workspace changes
socat -u UNIX-CONNECT:/tmp/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock - | while read -r line; do
  case $line in
    workspace*)
      hyprctl activeworkspace -j | jq '.id'
      ;;
  esac
done
