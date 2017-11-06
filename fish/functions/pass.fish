function pass --description 'fuzzy find password from lastpass-cli'
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
		set choice (cat $tmp_file | fzf | rg -o $lpass_id_regex)
		lpass show -cp $choice
	else
		lpass show -cp (cat $tmp_file | rg -o $lpass_id_regex)
	end

	rm $tmp_file
end
