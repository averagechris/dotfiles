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

  if not ps aux | grep -v grep | grep --silent 'emacs.* \-\-daemon'
    # if there is not an emacs server running, start one
    /usr/local/bin/emacs --daemon ^ /dev/null > /dev/null
  end

  if eval $TERMINAL_EMACS
    /usr/local/bin/emacsclient -t $passed_args
  else

    if not ps aux | grep -v grep | grep --silent 'emacsclient \-c'
      # create frame if one doesn't exist otherwise use existing gui frame
      set passed_args -c $passed_args
    end

    /usr/local/bin/emacsclient $passed_args > /dev/null &

  end
end
