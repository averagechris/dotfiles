function script_lpass
    # if logged out, log in
    if not lpass status -q
        /usr/local/bin/lpass login $EB_LAST_PASS_USER > /dev/null
    end

    set result (/usr/local/bin/lpass show -p -G "$argv")
    if echo $result | grep -iq "multiple matches found"
        set result (lpass show -p (lpass ls | grep -i -E "$argv" | fzf | rg -o --replace '$1' '\[id: (\d+)\]'))
    end

    echo $result
end
