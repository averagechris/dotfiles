function ws
	set query ""
	set search_engine_url 'https://duckduckgo.com/?q='
	set search_engine 'duckduckgo'
	set output "gui_browser"

	for arg in $argv
		switch arg
			case --url -u
				set output "url"
			case --terminal-browser -t
				set output "w3m"
			case --browser -b
				set output "gui_browser"
			case --google
				set search_engine_url 'https://google.com/?q='
				set search_engine 'google'
			case --duckduckgo
				set search_engine_url 'https://duckduckgo.com/?q='
				set search_engine 'duckduckgo'

			case '*'
				set query "$query%20$arg"
		end
	end

	set url_regex '^\s+(https?://)?(www.)?([a-z]+\.){1,3}[a-z]{2,4}(/.*)?'
	set results_temp_file (mktemp /tmp/ws_search_result.XXXXXXXXXX)

	echo "Searching $search_engine: $query"
	echo "..."
	w3m -dump "$search_engine_url$query" > $results_temp_file
	set user_selection (cat $results_temp_file | rg "$url_regex" | sed 's/ *//g' | fzf --preview "echo {}; echo \"--------------------\"; cat $results_temp_file | rg {} -B 4")

	if not echo $user_selection | rg -q "https?://"
		set user_selection "https://$user_selection"
	end

	rm $results_temp_file

	if test $output = 'url'
		echo $user_selection
	else if test $output = 'w3m'
		w3m $user_selection
	else if test $output = 'gui_browser'
		python -m webbrowser $user_selection
	else
		echo $user_selection
	end

end
