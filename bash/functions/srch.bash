function srch() {
    # wrapper around ripgrep and fzf.
    # USAGE: find top 5 files by num of matches:
    #       $ srch PATTERN -g GLOB -n5
    RG_ARGS=""
    N_LARGEST=0
    USE_FZF=1

    for arg in $@
    do
        case "$arg" in
            -n*)
                num=$(echo "$arg" | rg --replace '$1' -- '-n(\d+)')
                if ((num > 0)); then
                    RG_ARGS="$RG_ARGS -c"  # add count flag to rg
                    N_LARGEST=$num
                fi
                ;;
            --print)
                USE_FZF=0
                ;;
            *)
                RG_ARGS="$RG_ARGS $arg"
        esac
    done

    COMMAND="rg $RG_ARGS"

    if ((N_LARGEST > 0)); then
        PY_FILE=$(mktemp /tmp/srch_py.XXXXXXXXXXXXX)
        printf "
from heapq import nlargest
from sys import stdin

for match in nlargest($N_LARGEST, stdin.readlines(), key=lambda l: l.split(':')[-1]):
    print(match.strip())
" > $PY_FILE
        COMMAND="$COMMAND | python $PY_FILE"
    fi

    if ((USE_FZF > 0)); then
        FILTER_FILE_NAME='cut -f 1 -d :'
        FZF_COMMAND="fzf --preview 'cat {}'"
        COMMAND="$COMMAND | $FILTER_FILE_NAME | $FZF_COMMAND"
    fi

    eval $COMMAND

    if [ -f $PY_FILE ]; then
        rm $PY_FILE
    fi
}
