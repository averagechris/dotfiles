function rgvim
    set -l FZF_SELECTION (rg -Fi $argv | fzf -0 -1 --ansi)
    if [ $FZF_SELECTION ]
        /usr/local/bin/nvim "+/"(to_lower $argv) (echo "$FZF_SELECTION" | python -c "print \"$FZF_SELECTION\".split(':')[0]")
    end
end
