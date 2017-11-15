function colorize
		set STRING
		set COLOR $normal
		set BOLD_OUTPUT False

		for arg in $argv
				# echo 'arg' $arg
				# echo
			switch $arg
				case ls list
						set_color -c

				case --bold -b
						set BOLD_OUTPUT True
				case '--color-*'
						set COLOR (echo $arg | rg '(\-\-color\-)(\w+)' --replace '$2')

				case '*'
						set STRING $STRING $arg

			end
		end

		if echo (set_color -c) | grep -qw "$COLOR"

				set COLOR_ESC_SEQ (set_color $COLOR)

				if eval $BOLD_OUTPUT
						set COLOR_ESC_SEQ (set_color -o $COLOR)
				end

				echo $COLOR_ESC_SEQ $STRING (set_color $normal)
		else
				error_message "$COLOR is not an available color"
		end
end
