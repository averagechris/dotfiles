;; default emacs overrides
(setq tramp-default-method "ssh")

;; default spacemacs overrides
(setq-default dotspacemacs-themes '(spacemacs-light spacemacs-dark leuven))
(setq
 dotspacemacs-helm-resize t
 dotspacemacs-maximized-at-startup t
 dotspacemacs-search-tools '("ag" "grep")
 dotspacemacs-whitespace-cleanup 'trailing
 dotspacemacs-maximized-at-startup t
 dotspacemacs-fullscreen-at-startup nil)

(defvar personal-layer-use-black-formater nil "Toggle for running black on saving a buffer.")
