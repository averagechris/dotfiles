function ebmysql
    set host $EB_MYSQL_PROD_HOST
    set user $EB_OKTA_USER
    set lpass_lookup okta
    set password ""
    set args_to_pass

    # parse arguments into something that can be passed to mysql
    set index 2
    set last_was_flag 0
    for flag in $argv

        set arg $argv[$index]
        set arg_is_flag 1
        if not echo $arg | grep -qE '^\-+'
            set arg_is_flag 0
        end


        switch $flag
            # if lpass flag not used, defaulted to looking up okta, unless password is passed in with the -p flag
            case --lpass --lastpass --last-pass
                if test $arg_is_flag -eq 0
                    set lpass_lookup $arg
                else
                    error_message "--lpass --lastpass --last-pass flag requires an argument"
                end
                set last_was_flag 1

            # don't lookup the password with lpass, just use whatever is passed in here and send it to mysql directly
            case -p --pass --password
                if test $arg_is_flag -eq 0
                  set password $arg
                else
                    error_message "-p --pass --password flag requires an argument"
                    return 1
                end
                set last_was_flag 1

            # look up the host url from the environment, if none, use whatever is passed here directly
            case -h --host
                if test $arg_is_flag -eq 0
                    set tmp_host (find_in_env $arg)
                    set host $tmp_host
                    if test $tmp_host = ""
                      set host $arg
                    end
                else
                    error_message "-h and --host flag requires an argument"
                    return 1
                end
                set last_was_flag 1

            case -u --user
                if test $arg_is_flag -eq 0
                  set user $arg
                else
                  error_message "-u --user flag requires an argument"
                  return 1
                end
                set last_was_flag 1

            # pass these directly to mysql unless they are arguments to the flags handled above
            case '*'
                if test $last_was_flag -eq 0
                  set args_to_pass $args_to_pass $flag
                else
                  set last_was_flag 0
                end
        end
        set index (math $index + 1)
    end


    # if user is unset, ask for input interactively
    # this won't happen if your env variables are set properly
    if test $user = ""
        echo "Please input your user name for mysql:$host"
        read user
    end

    # if password is unset, get from lpass
    if test $password = ""
        set password (script_lpass $lpass_lookup)
    end

    if isatty stdout
      echo "preparing to log into mysql"
      echo "$host @ $user"
      echo "..."
    end

    /usr/local/bin/mysql $args_to_pass -h "$host" -u "$user" --password="$password"
end
