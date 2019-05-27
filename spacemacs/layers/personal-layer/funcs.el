(defun personal-layer/enable-minor-mode (pattern-and-minor-mode)
  "Enable minor mode if filename match the regexp. (regexp . minor-mode)."
  (if (buffer-file-name)
      (if (string-match (car pattern-and-minor-mode) buffer-file-name)
          (funcall (cdr pattern-and-minor-mode)))))

(defun personal-layer/multiply-at-pt (&optional amount)
  "Multiply the number currently under the cursor by amount. Uses the evil-numbers package."
  (interactive)
  (evil-numbers/inc-at-pt
   (*
    (string-to-number (current-word))
    (- (if amount amount (read-number "number to mulitiply by: ")) 1))))

(defun personal-layer/to-public-event-id ()
  "Multiply the number by 1003."
  (interactive)
  (personal-layer/multiply-at-pt 1003))

(defun personal-layer/to-private-event-id ()
  "Divide the number by 1003."
  (interactive)
  (personal-layer/multiply-at-pt (/ 1.0 1003)))

(defun personal-layer/to-public-user-id ()
  "Multiply the number by 1007."
  (interactive)
  (personal-layer/multiply-at-pt 1007))

(defun personal-layer/to-private-user-id ()
  "Divide the number by 1007."
  (interactive)
  (personal-layer/multiply-at-pt (/ 1.0 1007)))
