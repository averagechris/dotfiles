function sync_eventbrite_email
    # get new mail from imap.gmail.com
    if test (hostname) = "notmuch-thesogu"
        mbsync ebmail > /dev/null
    else
        ssh thesogu "mbsync ebmail" > /dev/null
    end

    if test $status -eq 0
      # index new mail
      notmuch new > /dev/null ^ /dev/stdout | grep -v "Note: Ignoring non-mail file:" | tee /dev/stderr
      # INFO: notmuch tags all new mail with: inbox new unread

      # add eventbrite tag
      notmuch tag +eventbrite -- tag:new "(to:@eventbrite.com or from:ccummings%@eventbrite.com)"
      notmuch tag +eventbrite -- tag:new AND not tag:personal


      # add tags to things that I want to call out, but still see in my inbox
      notmuch tag +jira_mention -- tag:new from:jira@eventbrite.com 'mentioned you on'
      notmuch tag +api_support -- tag:new "(from:api@eventbrite.com OR from:eventbrite-api@googlegroups.com)"

      # add tags to things I want to see, but not in my inbox
      notmuch tag +eventbrite_github -inbox -- tag:new from:notifications@github.com subject:eventbrite

      # filter out cruft that I don't really want to see
      notmuch tag -inbox +low_priority -- tag:new from:jira@eventbrite.com not 'mentioned you on'
      notmuch tag -inbox +deleted +sentry -- tag:new from:sentry@eventbrite.com or from:site-errors@eventbrite.com
      notmuch tag -inbox +low_priority +jenkins -- tag:new from:eng-ops@eventbrite.com
      notmuch tag -inbox +spam -- tag:new from:notifaction%@facebookmail.com

      # do clean up
      # tag messages from work email as sent
      notmuch tag -inbox -unread +sent -- from:ccummings@eventbrite.com tag:new
      # remove inbox tag from emails that I've replied to
      notmuch tag -inbox -unread -- tag:inbox tag:replied tag:new

      # remove new tag from everything
      notmuch tag -new -- tag:new
    end
end
