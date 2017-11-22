function srch_top
		set NUM 3
		set PRINT_COUNT False
		set RG_ARGS

		for arg in $argv
				switch $arg
						case '--top-*'
								set NUM (echo $arg | sed 's/--top-//')
								if not test $NUM -gt 0 ^ /dev/null
										error_message "srch_top error: $arg must contain a number"
										return 1
								end
						case --count -c
								set PRINT_COUNT True
						case '*'
								set RG_ARGS $RG_ARGS $arg
				end
		end

		set PY_SCRIPT "
import sys
from heapq import nlargest

files = sys.stdin.read().split()
key_func = lambda line: int(line.split(':').pop())

for l in nlargest($NUM, files, key=key_func):
    path, count = l.split(':')
    print(f'{count}: {path}')
"

		if eval $PRINT_COUNT
				rg -c $RG_ARGS | python3 -c $PY_SCRIPT
		else
				rg -c $RG_ARGS | python3 -c $PY_SCRIPT | sed 's/^.*: //'
		end

end
