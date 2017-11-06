function copy
	# if there are arguments, don't read from stdin, pipe them through
	if test (count $argv) -ne 0
		if test -f "$argv"
			cat $argv | pbcopy
		else
			echo $argv | pbcopy
		end
	else
		pbcopy
	end
end
