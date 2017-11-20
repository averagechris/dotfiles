function to_binary
	set NUM $argv[1]
    if test "$NUM" -ge '0' ^/dev/null
        echo "obase=2; $NUM" | bc
    else
        echo "$NUM is an invalid integer"
		return 1
    end
end
