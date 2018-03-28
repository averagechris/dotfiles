#!/usr/bin/fish
source ~/dotfiles/fish/functions/sync_all_email.fish
source ~/dotfiles/fish/functions/sync_eventbrite_email.fish

sync_all_email ^^ ~/email_sync_errors.log
echo (date) >> ~/email_sync_log.log
