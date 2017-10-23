function attach_or_new_tmux_session
    set session_name misc
    set confirmed False

    for arg in $argv
        switch $arg
            case -f --force
                set confirmed True
            case '*'
                if not echo $arg | grep -e '^-'
                    set session_name (to_lower $arg)
                end
        end
    end

    if not eval $confirmed
        echo "attach to tmux session: $session_name? [Y/n]"
        read user_input

        switch (to_lower $user_input)
            case y yes 1
                set confirmed True
            case '*'
                return 1  # indicates failure to attach
        end
    end

    if eval $confirmed
        if is_attached_tmux_session
            if not tmux has-session -t "$session_name" > /dev/null ^&1
                tmux new-session -ds $session_name
            end
            echo "to avoid nesting sessions, choose the $session_name session with C-b s"
        else
            echo "attaching to tmux session: $session_name"
            tmux new-session -As "$session_name"
        end
    end
end
