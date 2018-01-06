function srch -d 'wrapper around ripgrep and fzf. USAGE: find top 5 files by num of matches: $ srch PATTERN -g GLOB -n5'
  set RG_ARGS
  set N_LARGEST 0
  set USE_FZF 1

  for arg in $argv
    switch $arg
      case '-n*'
        set -l num (echo $arg | rg --replace '$1' -- '-n(\d+)')
        if test $num -gt 0
          set RG_ARGS $RG_ARGS "-c"
          set N_LARGEST $num
        end

      case '--print'
        set USE_FZF 0

      case '*'
        set RG_ARGS $RG_ARGS $arg
    end
  end

  set COMMAND "rg $RG_ARGS"

  if test $N_LARGEST -gt 0
    set PY_FILE (mktemp /tmp/srch_py.XXXXXXXXXXXXX)
    printf "
from heapq import nlargest
from sys import stdin

for match in nlargest($N_LARGEST, stdin.readlines(), key=lambda l: l.split(':')[-1]):
    print(match.strip())
" > $PY_FILE

    set COMMAND "$COMMAND | python $PY_FILE"

  end

  if test $USE_FZF -gt 0
    set FILTER_FILE_NAME 'cut -f 1 -d :'
    set FZF_COMMAND "fzf --preview 'cat {}'"
    set COMMAND "$COMMAND | $FILTER_FILE_NAME | $FZF_COMMAND"
  end

  eval $COMMAND

  if test -e "$PY_FILE"
    rm $PY_FILE
  end
end
