#!/usr/bin/env bash
# Focus a window by class or launch the application if not found
# Usage: focus-or-launch <window_class> <launch_command> [args...]

WINDOW_CLASS="$1"
shift
LAUNCH_CMD="$@"

# Check if window exists by class
if hyprctl clients -j | jq -e ".[] | select(.class | test(\"$WINDOW_CLASS\"; \"i\"))" > /dev/null 2>&1; then
    # Window exists, focus it
    hyprctl dispatch focuswindow "class:^($WINDOW_CLASS)$"
else
    # Window doesn't exist, launch it
    $LAUNCH_CMD &
fi
