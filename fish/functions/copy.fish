function copy
    set -l filename $argv[1]
    if test -f $argv[1]
        cat $filename | pbcopy
    else
        echo $argv | pbcopy
    end
end
