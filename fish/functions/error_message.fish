function error_message
		set ERR_STRING
		set RING_ALERT_BELL False
		set BOLD_OUTPUT False
		set ERR_COLOR 'red'
		set NO_COLOR False

		for arg in $argv
			switch $arg
				case --alert -a
					set RING_ALERT_BELL True
				case --bold -b
					set BOLD_OUTPUT True
				case --warn -w
						set ERR_COLOR 'yellow'
				case --no-color
					set NO_COLOR True

				case '*'
					set ERR_STRING $ERR_STRING $arg
			end
		end

		set ERR_MSG $ERR_STRING

		if not eval $NO_COLOR
				set COLOR_FLAGS "--color-$ERR_COLOR"
				if eval $BOLD_OUTPUT
						set COLOR_FLAGS '--bold' $COLOR_FLAGS
				end

				set ERR_MSG (colorize $COLOR_FLAGS $ERR_STRING)
		end

		echo "$ERR_MSG" > /dev/stderr


		if eval $RING_ALERT_BELL
				echo -ne '\a'
		end
end
