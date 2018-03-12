function ebmysql
    set host $EB_MYSQL_PROD_HOST
    set user $EB_OKTA_USER
    set password ""
    set lpass_lookup okta
    set args_to_pass

    set index 2
    for flag in $argv

        set arg $argv[$index]
        set arg_is_flag 1
        if not echo $arg | grep -E '^\-+'
            set arg_is_flag 0
        end


        switch $flag
            case --lpass --lastpass --last-pass
                if test $arg_is_flag -eq 0
                    set lpass_lookup $arg
                else
                    error_message "--lpass --lastpass --last-pass flag requires an argument"
                end

            case -p --pass --password
                if test $arg_is_flag -eq 0
                  set password $arg
                else
                    error_message "-p --pass --password flag requires an argument"
                    return 1
                end

            case -h --host
                if test $arg_is_flag -eq 0
                  set host $arg
                else
                    error_message "-h and --host flag requires an argument"
                    return 1
                end

            case -u --user
                if test $arg_is_flag -eq 0
                  set user $arg
                else
                  error_message "-u --user flag requires an argument"
                  return 1
                end

            case '*'
                set args_to_pass $args_to_pass $flag

        end
        set index (math $index + 1)
    end

    # if password is unset, get from lpass
    if test $password = ""
        set password (script_lpass $lpass_lookup)
    end

    /usr/local/bin/mysql -h "$host" -u "$user" -p"$password" $args_to_pass
end
