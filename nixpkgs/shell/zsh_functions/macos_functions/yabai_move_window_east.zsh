#!/usr/local/bin/zsh

# moves a yabai-managed window to a display leftward, wrapping around to the rightmost display
# if need be.

q_yabai() {
    yabai $@ > /dev/null 2>&1
}

q_yabai -m window --display prev || q_yabai -m window --display last > /dev/null 2>&1
q_yabai -m window --focus $(yabai -m query --windows --window | jq -re '.id')
