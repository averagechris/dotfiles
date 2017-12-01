function srch() {
    RG_ARGS=""
    N_LARGEST=0

    for arg in $@
    do
        case "$arg" in
            -n*)
                num=$(echo "$arg" | rg -o '\d+')
                if ((nag > 0)); then
                    RG_ARGS="$RG_ARGS -c"  # add count flag to rg
                    N_LARGEST=$num
                fi
                ;;
            *)
                RG_ARGS="$RG_ARGS $arg"
        esac
    done

    PY_SCRIPT="
from heapq import nlargest
from sys import stdin
from sys import stdout

for match_count in nlargest($N_LARGEST, stdin.readlines(), key=lambda l: l.split(':')[-1]):
    print(match_count.strip())
"

    if ((N_LARGEST > 0)); then
        rg $RG_ARGS | python -c "$PY_SCRIPT";
    else
        rg $RG_ARGS
    fi
}
