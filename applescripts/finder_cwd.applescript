tell application "Finder"
    try
        set curr_dir to (folder of the front window as alias)
    on error
        set curr_dir to (path to desktop folder as alias)
    end try
    POSIX path of curr_dir
end tell
