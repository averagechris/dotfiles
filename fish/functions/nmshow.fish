function nmshow
    # tag:api_support and tag:api_answered and tag:cx_can_answer and from:support@eventbrite.com
    notmuch-remote show --format=json $argv | parse_notmuch_email | parsed_email_jq
end
