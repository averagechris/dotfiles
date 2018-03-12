function ebpresto
  error_if_not_set EB_PRESTO_SERVER EB_PRESTO_USER
  if test $status -ne 0
      return $status
  end

  set PRESTO_PATH /usr/local/bin/presto
  if not test -e $PRESTO_PATH
      error_message "presto does not appear to be installed at $PRESTO_PATH"
  end

  eval $PRESTO_PATH --server $EB_PRESTO_SERVER --user $EB_PRESTO_USER $argv
end
