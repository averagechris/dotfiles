# remove empty lines, leading and trailing whitespace
sed '/^$/d' | sed -e 's/^ *//' | sed -e 's/ *$//'
