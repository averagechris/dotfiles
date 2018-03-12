function require_variables
    set COUNT_NOT_SET 0
    for arg in $argv
        if not set -q $arg
            echo $arg
            set COUNT_NOT_SET (math $COUNT_NOT_SET + 1)
        end
    end
    return $COUNT_NOT_SET
end
