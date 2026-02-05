#!/usr/bin/env bash
# Adjust volume based on scroll direction (throttled)

LOCKFILE="/tmp/eww-volume-scroll.lock"
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
    pamixer -i 1
else
    pamixer -d 1
fi
