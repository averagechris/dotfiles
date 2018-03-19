function require_bin_in_path
  set COUNT_NOT_IN_PATH 0
  for arg in $argv
    which $arg > /dev/null
    if test $status -ne 0
      set COUNT_NOT_IN_PATH (math $COUNT_NOT_IN_PATH + 1)
    end
  end
  return $COUNT_NOT_IN_PATH
end
