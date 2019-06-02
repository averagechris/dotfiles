;; Use this as a template for new dir locals

;;; Directory Local Variables
;;; For more information see (info "(emacs) Directory Variables")

((python-mode
  (fill-column . 120)
  (python-auto-set-local-pyenv-version . 'on-project-switch)

  ;; toggle for running black on save if non nil
  (personal-layer-use-black-formater . t)

  ;; this one is useful when the project is python 2 virtualenv
  (blacken-executable . "full path to black")))
