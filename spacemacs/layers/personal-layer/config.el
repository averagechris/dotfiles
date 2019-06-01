;; default emacs overrides
(setq tramp-default-method "ssh")

;; default spacemacs overrides
(setq-default dotspacemacs-themes '(spacemacs-light spacemacs-dark leuven))
(setq dotspacemacs-helm-resize t)
(setq dotspacemacs-maximized-at-startup t)
(setq dotspacemacs-search-tools '("ag" "grep"))
(setq dotspacemacs-whitespace-cleanup 'trailing)

(when (configuration-layer/package-usedp 'anaconda-mode)
  (setq anaconda-mode-localhost-address "localhost")
  ;; (setq python-shell-interpreter "usr/bin/python")
  )
