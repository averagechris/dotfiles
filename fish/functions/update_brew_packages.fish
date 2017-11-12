function update_brew_packages --description 'update selected (or all) brew packages'
	set no_confirm false

	for arg in $argv
		switch $arg
			case --all --force -f
				set no_confirm true


			case --help
				echo 'update selected brew packages'
				echo 'OPTIONS:'
				echo '    -all, --force -f: update every outdated package without confirmation'
				return 0
		end
	end

	set outdated_list_tmp_file (mktemp /tmp/outdated_list_tmp_file.XXXXXXXXXXX)
	brew outdated > $outdated_list_tmp_file

	if test (new_lines_count $outdated_list_tmp_file) -ne 0
		if no_confirm
			cat outdated_list_tmp_file | xargs brew upgrade
		else
			cat outdated_list_tmp_file | fzf -m -n 1 --tac --header='choose packages to update with tab' | xargs brew upgrade
		end
	end

	rm $outdated_list_tmp_file
end
