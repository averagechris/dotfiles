function is_attached_tmux_session
    tmux ls > /dev/stdout ^&1 | read tmux_sessions
    if not echo $tmux_sessions | grep "(attached)" > /dev/null ^&1
        return 1
    end
end
