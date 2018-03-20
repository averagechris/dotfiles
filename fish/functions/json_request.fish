function json_request
  error_if_bin_not_available jq curl; or return 1

  set HELP_MSG 'USAGE: json_request [REQUIRED: (URL) ] [OPTIONAL: (ARGS PASSED TO CURL) (OTHER OPTIONAL ARGS) ]

REQUIRED ARGUMENTS:
    * URL

OPTIONS:
    * --dry-run -- dont actually send the request via curl
    * --log-parse-failures -- cat out non-json responses
    * --jq="" -- pass arguments, flags, options to jq
    * --print-curl-command -- pretty print out the resulting command to easily share with others
    * --share-to-clipboard -- dry run and print resulting command to clipboard
    * any flag or option for curl -- see `man curl` for details

EXAMPLES:
    * json_request https://www.evbqaapi.com/v3/users/me/ -H "Authorization: Bearer SOME-TOKEN"
    * json_request https://www.evbqaapi.com/v3/users/me/owned_events/ --jq="[.events[] | select(.status == "live")], .pagination"

INFO:
    * every argument is passed directly to curl _except_ the --jq="" argument.
    * the quoted, space delimited arguments to the right of --jq= are passed directly to jq
    * uses the curl installed by homebrew if it exists

ERRORS:
    * 1 - required arguments are missing
    * 2 - one of the required commands or functions is not available in the path
    * 3 - the response cannot be parsed as json

see `man curl` and `man jq` for help with flags and options
'

  set CAT_JSON_PARSE_FAILURES false
  set CURL_ARGS -sS
  set DRY_RUN false
  set JQ_ARGS '.'
  set PRINT_CURL_COMMAND_OUT false
  set PRINT_TO_CLIPBOARD false
  set RETURN_STATUS_CODE 0


  for arg in $argv
    switch $arg
      case '--help'
          echo "$HELP_MSG"
          return 0

      case '--dry-run'
          set DRY_RUN true

      case '--print-curl-command'
          set PRINT_CURL_COMMAND_OUT true

      case '--share-to-clipboard'
          set DRY_RUN true
          set PRINT_CURL_COMMAND_OUT true
          set PRINT_TO_CLIPBOARD true

      case '--jq=*'
        set JQ_ARGS (echo $arg | cut -d '=' -f 2)

      case '--log-parse-failures'
        set CAT_JSON_PARSE_FAILURES true

      case '*'
        set CURL_ARGS $CURL_ARGS (simple_quote $arg)
    end
  end

  if test (count $CURL_ARGS) -lt 2
    error_message "missing required argument: URL"
    return 1
  end

  # use homebrew curl if it exists
  set CURL_COMMAND /usr/local/opt/curl/bin/curl
  if not test -e $CURL_COMMAND
      set CURL_COMMAND curl
  end

  if eval $PRINT_CURL_COMMAND_OUT
      # TODO: find a way to format this into something that's easy for someone to copy and paste into
      # another terminal
    set pretty_command "$CURL_COMMAND $CURL_ARGS"

    if eval $PRINT_TO_CLIPBOARD
        echo $pretty_command | pbcopy
    else
        echo $pretty_command
    end

  end

  if not eval $DRY_RUN
    set JSON_FILE (mktemp /tmp/json_request.XXXXXXXXXX)
    eval $CURL_COMMAND $CURL_ARGS > $JSON_FILE

    # pretty format json file if can be parsed as json
    cat $JSON_FILE | jq $JQ_ARGS ^ /dev/null

    if test $status -ne 0
      # cat out raw response if cannot be parsed as json
      error_message "Response could not be parsed from request"
      error_message -w "$CURL_COMMAND $CURL_ARGS"

      if eval $CAT_JSON_PARSE_FAILURES
        cat $JSON_FILE
      end

      set RETURN_STATUS_CODE 3
    end

    rm $JSON_FILE
  end
  return $RETURN_STATUS_CODE
end
