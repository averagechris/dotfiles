function srch
  set RG_ARGS
  set N_LARGEST 0

  for arg in $argv
    switch $arg
      case '-n*'
        set -l num (echo $arg | rg -o '\d+')
        if test $num -gt 0
          set RG_ARGS $RG_ARGS "-c"
          set N_LARGEST $num
        end

      case '*'
        set RG_ARGS $RG_ARGS $arg
    end
  end

  set PY_SCRIPT "
from heapq import nlargest
from sys import stdin
from sys import stdout

for match_count in nlargest($N_LARGEST, stdin.readlines(), key=lambda l: l.split(':')[-1]):
    print(match_count.strip())
"

  if test $N_LARGEST -gt 0
    rg $RG_ARGS | python -c "$PY_SCRIPT"
  else
    rg $RG_ARGS
  end
end
