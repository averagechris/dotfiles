function cdfinder
    set -l current_path (run_apple_script '
        tell application "Finder"
            try
                set currFolder to (folder of the front window as alias)
            on error
                set currFolder to (path to home folder as alias)
            end try

        return (POSIX path of currFolder)
        end tell
    ')
    echo "	 Finder is at: $current_path, changing directories"
    cd "$current_path"
end
