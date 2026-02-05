#!/usr/bin/env bash
# Adjust brightness based on scroll direction (throttled)

LOCKFILE="/tmp/eww-brightness-scroll.lock"
THROTTLE_MS=100

# Check if lock exists and is recent
if [ -f "$LOCKFILE" ]; then
    lock_age=$(( $(date +%s%3N) - $(cat "$LOCKFILE") ))
    if [ "$lock_age" -lt "$THROTTLE_MS" ]; then
        exit 0
    fi
fi

# Update lock timestamp
date +%s%3N > "$LOCKFILE"

direction="$1"

if [ "$direction" = "up" ]; then
    brightnessctl set 1%+
else
    brightnessctl set 1%-
fi
