function rm() {
    if echo "$@" | grep -qE '(^|\s+)(/|~)\*?\b'; then
        echo "you do not want to delete / or ~ ... dumbass" > /dev/stderr
        return 1
    fi;

    /bin/rm $argv
}
