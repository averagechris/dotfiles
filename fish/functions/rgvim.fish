function rgvim
    set -l choice (rg -Fil $argv | fzf -0 -1 --ansi --preview "cat {} | rg $argv --context 5")
    if [ $choice ]
        /usr/local/bin/nvim "+/"(to_lower $argv) (python -c "print \"$choice\".split(':')[0]")
    end
end
