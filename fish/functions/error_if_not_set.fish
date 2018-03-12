function error_if_not_set
  set NOT_SET (require_variables $argv)
  set COUNT_NOT_SET $status

  for arg in $NOT_SET
      error_message "$arg is not set and is required"
  end

  return $COUNT_NOT_SET
end
