function prettify_terminal_command
    set result
    set count 1
    for arg in $argv

        echo $arg

        if test $count -gt 1
            set count (math $count + 1)
            set next $argv[$count]

          if test $count -eq 2
              set result $result (simple_quote $arg)
          end

        else  # this should always be the base command
            set result $arg
        end

        # echo $arg \\
    end

    for w in $result
        echo $w
    end
end
