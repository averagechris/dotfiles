;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-
(setq user-full-name "Chris Cummings"
      user-mail-address "chris@thesogu.com")

(setq doom-theme 'doom-one-light)
(setq display-line-numbers-type nil)

(after! treemacs (setq +treemacs-git-mode 'deferred))


;; ;;;;;;;;;;;;;
;; KEYBINDINGS
;; ;;;;;;;;;;;;;

(map! :leader
      :desc "Comment line" :nv "tc" #'comment-line
      :desc "Sort lines" :nv "as" #'sort-lines)

;; while in python mode
(map! :leader :localleader :mode python-mode
      :desc "Insert breakpoint with context" :n "b" #'(lambda ()
                                                        (interactive)
                                                        (progn
                                                          (evil-insert-newline-above)
                                                          (insert "breakpoint(context=12)")
                                                          (indent-according-to-mode))))

(set-email-account! "personal"
                    '((mu4e-sent-folder . "/personal/Sent")
                      (mu4e-drafts-folder . "/personal/Drafts")
                      (mu4e-trash-folder . "/personal/Trash")
                      (mu4e-refile-folder . "/personal/Archive"))
                    t)

(set-email-account! "icloud"
                    '((mu4e-sent-folder . "/icloud/Sent Messages")
                      (mu4e-drafts-folder . "/icloud/Drafts")
                      (mu4e-trash-folder . "/icloud/Deleted Messages")
                      (mu4e-refile-folder . "/icloud/Archive"))
                    t)

(set-email-account! "sure"
                    '((mu4e-sent-folder . "/sure/[Gmail]/Sent Mail")
                      (mu4e-drafts-folder . "/sure/[Gmail]/Drafts")
                      (mu4e-trash-folder . "/sure/[Gmail]/Trash")
                      (mu4e-refile-folder . "/sure/[Gmail]/All Mail"))
                    t)
