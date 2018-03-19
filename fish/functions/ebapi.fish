function ebapi
    set host $EB_API_QA_URL
    set host_pattern qa
    set expansions
    set parameters
    set path
    set token
    set args_to_pass

    for arg in $argv
        switch $arg
            case '--help'
                echo USAGE:
                echo 'ebapi [ENDPOINT] [FLAGS]'
                echo 'FLAGS AVAILABLE: -h -p -e -t'
                echo 'host, parameter, expansion, token'
                echo 'any other arguments are passed directly to curl'
                return 0

            case '--host=*' '--env=*'
                set host_pattern (echo $arg | cut -d '=' -f 2)
                set host (find_in_env "api.*$host_pattern")
                if test $host = ""
                    set host $arg
                end

            case '-e=*' '--expansions=*'
                set expansions (echo $arg | cut -d '=' -f 2)

            case '-t=*' '--token=*'
                set token (echo $arg | cut -d '=' -f 2)

            case '-p=*' '--param=*' '--params=*' '--parameters=*'
                set parameters "$parameters&"(echo $arg | rg '(\-{1,2}p\w*=)(.*)' -o --replace '$2')

            case '/*/'
                set path $arg

            case '*'
                set args_to_pass $args_to_pass $arg
        end
    end

    set token_pattern "$host_pattern.*token"
    while not test -n "$token"
        set token (script_lpass $token_pattern)
        if not test -n "$token"
            echo "A token can't be found in last pass with pattern: '$token_pattern'"
            echo "try searching for your token in lastpass"
            echo "or CTRL C to exit"
            read token_pattern -P '>>> '
        end
    end

    set url "$host$path?token=$token&expand=$expansions$parameters"
    json_request $url $args_to_pass
end
