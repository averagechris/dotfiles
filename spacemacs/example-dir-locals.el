;; Use this as a template for new dir locals

;;; Directory Local Variables
;;; For more information see (info "(emacs) Directory Variables")

(

 ;; python project examples
 (python-mode
  (fill-column . 120)
  (python-auto-set-local-pyenv-version . 'on-project-switch)

  ;; toggle for running black on save if non nil
  (personal-layer-use-black-formater . t)

  ;; these are useful when the project is python 2 virtualenv
  (blacken-executable . "full path to black")
  (flycheck-python-mypy-executable . "full path to mypy")

  ;; useful for very django-y projects, or projects with local dependencies
  (python-shell-process-environment. "DJANGO_SETTINGS_MODULE=full path to settings module")
  (eval . (progn
            (add-to-list 'python-shell-extra-pythonpaths "full path to extra dependencies (or django apps)")
            (add-to-list 'python-shell-extra-pythonpaths "more full path to extra dependencies (or django apps)")))
  ))
