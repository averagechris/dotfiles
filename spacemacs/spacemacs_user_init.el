(defun _invoke_init ()
  (defun enable-minor-mode-by-pattern (my-pair)
    "Enable minor mode if filename match the regexp.  MY-PAIR is a cons cell (regexp . minor-mode)."
    (if (buffer-file-name)
        (if (string-match (car my-pair) buffer-file-name)
            (funcall (cdr my-pair)))))

  (defun file-read-lines (path)
    "Return a list of strings, one for each line in the file at `path`"
    (with-temp-buffer
      (insert-file-contents path)
      (split-string (buffer-string) "\n" t)))
)
