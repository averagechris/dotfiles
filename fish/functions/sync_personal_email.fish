function sync_personal_email
    # get new mail from imap.fastmail.com
    if test (hostname) = "notmuch-thesogu"
        mbsync fastmail > /dev/null
    else
        ssh thesogu "mbsync fastmail" > /dev/null
    end

    if test $status -eq 0
        # index new mail
        notmuch new > /dev/null ^ /dev/stdout | grep -v "Note: Ignoring non-mail file:" | tee /dev/stderr
        # INFO: notmuch tags all new mail with: inbox new unread

        # add personal tag
        notmuch tag +personal -- tag:new AND "(from:chris@thesogu.com or to:chris@thesogu.com or from:mistahcummings@gmail.com or to:mistahcummings%@gmail.com)"

        # add tags to things that I want to call out, but still see in my inbox

        # add tags to things I want to see, but not in my inbox

        # archive stuff that's important but I don't want in inbox
          # receipts and order confirmations
        notmuch tag -inbox +receipts -- tag:new AND tag:personal "(receipt or confirmation or purchase or payment)" and "(from:lyft or form:uber or from:square or from:amazon or homedepot or paypal)" not subject:review

        # filter out cruft that I don't really want to see
        notmuch tag -inbox +social_media_notifications -- tag:new AND tag:personal "(from:@twitter.com or from:@facebookmail.com)"

        # remove new tag from everything
        notmuch tag -new tag:new

        # do clean up
        # tag messages from work email as sent
        notmuch tag -inbox -unread +sent -- from:chris@thesogu.com AND tag:new
        # remove inbox tag from emails that I've replied to
        notmuch tag -inbox -unread -- tag:inbox AND tag:replied
    end
end