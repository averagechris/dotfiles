(defun _invoke_config ()
  (setq helm-ag-base-command "rg --no-heading")

  (add-hook
  'web-mode-hook
  #'(lambda () (enable-minor-mode-by-pattern '("\\.jsx?\\'" . prettier-js-mode))))

  ;; set javascript modes to indentation to two spaces
  (setq-default
  js2-basic-offset 2
  css-indent-offset 2
  web-mode-markup-indent-offset 2
  web-mode-code-indent-offset 2
  web-mode-attr-indent-offset 2)

  (autoload 'notmuch  "/usr/local/share/emacs/site-lisp/notmuch" "notmuch mail program" t)
  (setq notmuch-command "notmuch-remote")

  (setq smtpmail-multi-accounts
        (quote ((work . ("ccummings@eventbrite.com"
                         "smtp.gmail.com"
                         587
                         "ccummings@eventbrite.com"
                         nil nil nil nil))
                (personal . ("chris@thesogu.com"
                             "smtp.fastmail.com"
                             587
                             "chris@thesogu.com"
                             nil nil nil nil)))))
  (setq smtpmail-multi-default-account 'work)
  (setq smtpmail-multi-associations
        (quote (("ccummings@eventbrite.com" work)
                ("chris@thesogu.com" personal))))
  (setq send-mail-function 'smtpmail-multi-send-it)
  (setq message-kill-buffer-on-exit t)
  (setq smtpmail-debug-info t)
  (setq smtpmail-debug-verbose t)
)
