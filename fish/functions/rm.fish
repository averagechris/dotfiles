function rm
    if echo $argv | grep -qE '(^|\s+)(/|~)\*?\b'
        error_message "you do not want to delete / or ~... dumbass"
        return 1
    end

    /bin/rm $argv
end
