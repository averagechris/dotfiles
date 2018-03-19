function simple_quote
  for arg in $argv
    if echo $arg | contains_spaces
      echo "'$arg'"
    else
      echo $arg
    end
  end
end
