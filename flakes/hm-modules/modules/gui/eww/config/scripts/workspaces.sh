#!/usr/bin/env bash
# Get Hyprland workspaces

get_workspaces() {
  monitor="${1:-}"
  # Filter out special workspaces (like scratchpad which has ID -98)
  # Only include regular workspaces with positive IDs
  if [[ -n "$monitor" ]]; then
    hyprctl workspaces -j | jq -c --arg monitor "$monitor" '[.[] | select(.monitor == $monitor) | .id | select(. >= 0)] | sort'
  else
    hyprctl workspaces -j | jq -c '[.[].id | select(. >= 0)] | sort'
  fi
}

# Initial output
get_workspaces

# Listen for workspace changes using correct socket path
socat -u UNIX-CONNECT:"$XDG_RUNTIME_DIR"/hypr/"$HYPRLAND_INSTANCE_SIGNATURE"/.socket2.sock - | while read -r line; do
  case $line in
    workspace*|createworkspace*|destroyworkspace*)
      get_workspaces
      ;;
  esac
done
