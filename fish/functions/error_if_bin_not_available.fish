function error_if_bin_not_available
  set NOT_SET (require_bin_in_path $argv)
  set COUNT_NOT_SET $status

  for arg in $NOT_SET
      error_message "$arg is not set and is required"
  end

  return $COUNT_NOT_SET
end
