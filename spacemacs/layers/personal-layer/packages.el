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
    helm-ag
    prettier-js
    smtpmail-multi
    web-mode
   ))

(defun personal-layer/init-prettier-js()
  "Own prettier-js package.")
(defun personal-layer/init-smtpmail-multi()
  "Own smtpmail-multi package.")

(defun personal-layer/post-init-helm-ag ()
  "Configure helm-ag package."
  (setq helm-ag-base-command "rg --no-heading"))

(defun personal-layer/post-init-web-mode ()
  "Enable prettier-js-mode if using .js or .jsx buffer."
  (add-to-list 'auto-mode-alist '("\\.js\\'" . web-mode))
  (add-hook
   'web-mode-hook
   #'(lambda () (enable-minor-mode '("\\.js\\'" . prettier-js-mode)))))

;;; packages.el ends here
