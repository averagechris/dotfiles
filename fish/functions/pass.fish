function pass --description 'fuzzy find passwords from lastpass-cli'

	for arg in $argv
		switch $arg
			case --help
				echo 'pass: fuzzy find passwords from lastpass-cli'
				echo 'USEAGE: pass [pattern]'
				echo 'Note: most flags will get passed to ripgrep'
				return 0
		end
	end

	# filter account list by argv, store in tmp_file
	set tmp_file (mktemp /tmp/getpass_tmp_file.XXXXXXXXXXXXXXX)
	lpass ls | rg -i "$argv" > $tmp_file

	set match_count (new_lines_count $tmp_file)
	set lpass_id_regex '\d{5,}'

	if test $match_count -eq 0
		echo "Could not find $argv -" (lpass status)
		return 1

	else if test $match_count -ge 2
		# fuzzy find account, pass account id back, lpass finds then copies pass to clipboard
		set choice (cat $tmp_file | fzf)

		if test $status -eq 130
			# fzf was quit without a choice
			return 0
		end

		set choice (echo $choice | rg -o $lpass_id_regex)
		lpass show -cp $choice
	else
		lpass show -cp (cat $tmp_file | rg -o $lpass_id_regex)
	end

	rm $tmp_file
end
