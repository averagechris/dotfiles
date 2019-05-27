;;; packages.el --- personal-layer layer packages file for Spacemacs.
;;
;; Copyright (c) 2012-2017 Sylvain Benner & Contributors
;;
;; Author: Chris Cummings <chris@thesogu.com>
;; URL: https://github.com/syl20bnr/spacemacs
;;
;; This file is not part of GNU Emacs.
;;
;;; License: GPLv3

;;; Commentary:

;; - Otherwise, PACKAGE is already referenced by another Spacemacs layer, so
;;   define the functions `personal-layer/pre-init-PACKAGE' and/or
;;   `personal-layer/post-init-PACKAGE' to customize the package as it is loaded.

;;; Code:

(defconst personal-layer-packages
  '(
    docker-tramp
    evil-mode
    git-commit
    git-gutter+
    helm-ag
    prettier-js
    smtpmail-multi
    web-mode
   ))

(defun personal-layer/init-docker-tramp ()
  "Own docker-tramp package.")

(defun personal-layer/init-prettier-js ()
  "Own prettier-js package.")
(defun personal-layer/init-smtpmail-multi ()
  "Own smtpmail-multi package.")

(defun personal-layer/post-init-evil-mode ()
  "Configure evil-mode.")

(defun personal-layer/post-init-git-commit ()
  "Configure git-commit."
  (global-git-commit-mode t))

(defun personal-layer/post-init-git-gutter+ ()
  "Configure get-gutter+."

  ;; https://github.com/nonsequitur/git-gutter-plus/pull/39
  (defun git-gutter+-remote-default-directory (dir file)
    (let* ((vec (tramp-dissect-file-name file))
           (method (tramp-file-name-method vec))
           (user (tramp-file-name-user vec))
           (domain (tramp-file-name-domain vec))
           (host (tramp-file-name-host vec))
           (port (tramp-file-name-port vec)))
      (tramp-make-tramp-file-name method user domain host port dir)))

  (defun git-gutter+-remote-file-path (dir file)
    (let ((file (tramp-file-name-localname (tramp-dissect-file-name file))))
      (replace-regexp-in-string (concat "\\`" dir) "" file))))

(defun personal-layer/post-init-helm-ag ()
  "Configure helm-ag package."
  ;; use rg instead of ag, ag must still be installed
  (setq helm-ag-base-command "rg --no-heading"))

(defun personal-layer/post-init-web-mode ()
  "Enable prettier-js-mode if using .js or .jsx buffer."
  (add-to-list 'auto-mode-alist '("\\.js\\'" . web-mode))
  (add-hook
   'web-mode-hook
   #'(lambda () (personal-layer/enable-minor-mode '("\\.js\\'" . prettier-js-mode)))))

;;; packages.el ends here
