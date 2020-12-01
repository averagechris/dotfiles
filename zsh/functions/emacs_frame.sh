# tries to open an emacsclient new window
# if a server isn't started, starts one
# and tries to connect to it repeatedly
# until ~30 seconds are up then gives up
#
# meant to be called from GUI apps or hot keys
# notifications are sent to the macos notification
# widget / tray thing

emacs_frame_quiet_emacsclient() {
    emacsclient -nc > /dev/null 2>&1
}

emacs_frame_start_emacs() {
    terminal-notifier -message "Emacs server starting"

    brew services restart 'emacs-plus@28' > /dev/null 2>&1

    START_EMACS_COUNT=100
    until [ "$START_EMACS_COUNT" -eq 0 ] || emacs_frame_quiet_emacsclient;
      do sleep .25 && let START_EMACS_COUNT=START_EMACS_COUNT-1; done;

    [ "$START_EMACS_COUNT" -eq 0 ] && terminal-notifier -message "Emacs server failed to start"
}

emacs_frame_quiet_emacsclient || emacs_frame_start_emacs
