function emacs --description 'convenience wrapper for starting an emacs client and server'
  # open emacs in gui by default
  set TERMINAL_EMACS false
  set passed_args

  for arg in $argv
    switch $arg
      case -t --terminal
        set TERMINAL_EMACS true
      case '*'
        set passed_args $passed_args $arg
    end
  end

  if not ps aux | grep -v grep | grep 'emacs.* \-\-daemon' --silent
    /usr/local/bin/emacs --daemon ^ /dev/null > /dev/null
  end

  if eval $TERMINAL_EMACS
    /usr/local/bin/emacsclient $passed_args > /dev/null &
  else
    /usr/local/bin/emacsclient -c $passed_args > /dev/null &
  end
end
