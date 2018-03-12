function script_lpass
    # if logged out, log in
    if not lpass status -q
        /usr/local/bin/lpass login $EB_LAST_PASS_USER
    end

    /usr/local/bin/lpass show -p -G "$argv"
end
