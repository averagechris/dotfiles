function sync_eventbrite_email
    # get new mail from imap.gmail.com
    if test (hostname) -eq "notmuch-thesogu"
        mbsync ebmail > /dev/null
    else
        ssh thesogu "mbsync ebmail" > /dev/null
    end

    if test $status -eq 0
      # index new mail
      notmuch new > /dev/null ^ /dev/stdout | grep -v "Note: Ignoring non-mail file:" | tee /dev/stderr

      # notmuch is configured to tag all new mail with: inbox new unread

      # add tags to things that I want to call out, but still see in my inbox
      notmuch tag +jira_mention -- tag:new from:jira@eventbrite.com 'mentioned you on'

      # add tags to things I want to see, but not in my inbox
      notmuch tag +api_support -inbox -- tag:new "(from:api@eventbrite.com OR from:eventbrite-api@googlegroups.com)"
      notmuch tag +eventbrite_github -inbox -- tag:new from:notifications@github.com subject:eventbrite

      # filter out cruft that I don't really want to see
      notmuch tag -inbox +low_priority -- tag:new from:jira@eventbrite.com not 'mentioned you on'
      notmuch tag -inbox +deleted +sentry -- from:sentry@eventbrite.com or from:site-errors@eventbrite.com
      notmuch tag -inbox +low_priority +jenkins -- from:eng-ops@eventbrite.com
      notmuch tag -inbox +spam -- from:notifaction%@facebookmail.com

      # remove new tag from everything
      notmuch tag -new tag:new

      # do clean up
      # tag messages from work email as sent
      notmuch tag -inbox -unread +sent -- from:ccummings@eventbrite.com tag:new
      # remove inbox tag from emails that I've replied to
      notmuch tag -inbox -unread -- tag:inbox tag:replied

    end
end
