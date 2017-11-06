function new_lines_count
	# if there are arguments, don't read from stdin, pipe them through
	if test (count $argv) -ne 0
		if test -f "$argv"
			cat "$argv" | wc -l | rg -o '\d{1,}'
		else
			echo "$argv" | wc -l | rg -o '\d{1,}'
		end
	else
		wc -l | rg -o '\d{1,}'
	end
end
