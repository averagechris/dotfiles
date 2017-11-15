function pyactivate --description 'activate a pyenv virtualenv by name'

		set VENV_NAME

		for arg in $argv
			switch $arg
				case --help
					echo 'USAGE:'
					echo "    pyactivate [venv_name]    activate a pyenv-virtualenv by name"
					echo '    pyactivate ls             list available pyenv-virtualenvs'
					echo
					echo '    options:'
					echo '        --help                display this message'
					return 0

				case ls list
				    pyenv versions
					return 0

				case '--*'
						error_message --warn --bold "$arg is an unrecognized flag"
						return 9

				case '*'
					if test -n $VENV_NAME
						set VENV_NAME $arg
					end
			end
		end

		if not test -n "$VENV_NAME"
			error_message --alert 'virtual environment name is a required arguemnt'
			return 1

		else

		    if echo (pyenv versions) | grep -qw "$VENV_NAME"
				set VENV_DIR "$PYENV_ROOT/versions/$VENV_NAME"
				source $VENV_DIR/bin/activate.fish

			else
				error_message 'virtual env does not exist'
				return 2
			end

		end
end
