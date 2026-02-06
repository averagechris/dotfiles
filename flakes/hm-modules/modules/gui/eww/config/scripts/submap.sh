#!/usr/bin/env bash
# Listen to Hyprland IPC for submap changes
# Outputs the current submap name, or empty string if in default/global submap

socat -U - UNIX-CONNECT:"$XDG_RUNTIME_DIR"/hypr/"$HYPRLAND_INSTANCE_SIGNATURE"/.socket2.sock 2>/dev/null | while read -r line; do
    case "$line" in
        submap*)
            # Extract submap name from "submap>>NAME"
            submap="${line#submap>>}"
            if [ "$submap" = "reset" ]; then
                echo ""  # Global/default submap - show nothing
            else
                echo "$submap"
            fi
            ;;
    esac
done
