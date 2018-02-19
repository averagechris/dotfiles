emacs() {
    if ! ps aux | grep -v grep | grep -q 'emacs.* \-\-daemon'; then
        /usr/local/bin/emacs --daemon > /dev/null 2>&1
    fi;

    passed_args="$@"

    if [ $(echo -n "$passed_args" | wc -c) -lt "1" ]; then
        echo "USAGE: emacs [PATH TO FILE] [OPTIONAL ARGS PASSED TO EMACS CLIENT]"
        return 1
    fi;

    if ! ps aux | grep -v grep | grep -q 'emacsclient -c'; then
        # create an emacsclient frame if one does not exist otherwise use existing frame
        passed_args="-c $passed_args"
    fi;

    /usr/local/bin/emacsclient "$passed_args" > /dev/null &
}
