#!/usr/bin/env bash
# Get active Hyprland workspace

monitor="${1:-}"

get_active_workspace() {
  if [[ -n "$monitor" ]]; then
    hyprctl monitors -j | jq --arg monitor "$monitor" '.[] | select(.name == $monitor) | .activeWorkspace.id'
  else
    hyprctl activeworkspace -j | jq '.id'
  fi
}

# Initial output
get_active_workspace

# Listen for workspace changes using correct socket path
socat -u UNIX-CONNECT:"$XDG_RUNTIME_DIR"/hypr/"$HYPRLAND_INSTANCE_SIGNATURE"/.socket2.sock - | while read -r line; do
  case $line in
    workspace*|focusedmon*)
      get_active_workspace
      ;;
  esac
done
