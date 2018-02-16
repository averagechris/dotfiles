function json_request
  curl -sS $argv | python -m 'json.tool'
end
