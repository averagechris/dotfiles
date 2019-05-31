(defun personal-layer/enable-minor-mode (pattern-and-minor-mode)
  "Enable minor mode if filename match the regexp. (regexp . minor-mode)."
  (if (buffer-file-name)
      (if (string-match (car pattern-and-minor-mode) buffer-file-name)
          (funcall (cdr pattern-and-minor-mode)))))

(defun personal-layer/start-end-points-current-word ()
  "Return start and end points of the current-word."
  (interactive)
  (let ((word-pattern  "-_A-Za-z0-9")
        (start-pnt nil)
        (end-pnt nil))
    (skip-chars-forward word-pattern)
    (setq end-pnt (point))
    (skip-chars-backward word-pattern)
    (setq start-pnt (point))
    (cons start-pnt end-pnt)))

(defun personal-layer/remove-leading (&optional char)
  "Remove the leading char from the current-word."
  (interactive)
  (let ((start-point (car (personal-layer/start-end-points-current-word)))
        (char (if char char (read-string "character to remove: ")))
        (end-point nil))
    (goto-char start-point)
    (skip-chars-forward char)
    (setq end-point (point))
    (delete-region start-point end-point)))

(when (configuration-layer/package-usedp 'evil-numbers)
  ;; These functions depend on evil-numbers

  (defun personal-layer/multiply-at-pt (&optional amount)
    "Multiply the number currently under the cursor by amount."
    (interactive)
    (evil-numbers/inc-at-pt
      (*
        (string-to-number (current-word))
        (-
         (if amount amount (read-number "number to mulitiply by: "))
         1))))

  (defun personal-layer/to-public-event-id ()
    "Multiply the number by 1003."
    (interactive)
    (progn
      (personal-layer/multiply-at-pt 1003)
      (personal-layer/remove-leading "0")))

  (defun personal-layer/to-private-event-id ()
    "Divide the number by 1003."
    (interactive)
    (progn
      (personal-layer/multiply-at-pt (/ 1.0 1003))
      (personal-layer/remove-leading "0")))

  (defun personal-layer/to-public-user-id ()
    "Multiply the number by 1007."
    (interactive)
    (personal-layer/multiply-at-pt 1007))

  (defun personal-layer/to-private-user-id ()
    "Divide the number by 1007."
    (interactive)
    (progn
      (personal-layer/multiply-at-pt (/ 1.0 1007))
      (personal-layer/remove-leading "0"))))
