;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-
(setq user-full-name "Chris Cummings"
      user-mail-address "chris@thesogu.com")

(setq doom-theme 'doom-one)
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

(set-email-account! "chris@thesogu.com"
                    '((mu4e-sent-folder . "/chris@thesogu.com/Sent")
                      (mu4e-drafts-folder . "/chris@thesogu.com/Drafts")
                      (mu4e-trash-folder . "/chris@thesogu.com/Trash")
                      (mu4e-refile-folder . "/chris@thesogu.com/Archive"))
                    t)
