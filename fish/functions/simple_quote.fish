function simple_quote
  error_if_not_set URL_REGEX

  for arg in $argv
    set should_quote false

    if echo $arg | contains_spaces
      set should_quote true
    end

    if echo $arg | grep -Eq "$URL_REGEX"
        set should_quote true
    end

    if eval $should_quote
        echo "'$arg'"
    else
        echo $arg
    end
  end
end
