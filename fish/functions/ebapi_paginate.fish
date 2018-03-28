function ebapi_paginate
    set results_file (mktemp /tmp/ebapi_paginate.XXXXXX)
    ebapi $argv > $results_file

    set pagination_object (echo $results_file | jq -c '.pagination')
    set continuation_token (echo $pagination_object | jq '.continuation')

    rm $results_file
end
