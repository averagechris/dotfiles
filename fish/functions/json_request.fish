function json_request
  # use homebrew curl if it exists
  set CURL_PATH /usr/local/opt/curl/bin/curl
  if not test -e eval $CURL_PATH
      set CURL_PATH /usr/bin/curl
  end

  eval $CURL_PATH -sS $argv | python -m 'json.tool'
end
