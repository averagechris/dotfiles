;;; packages.el --- misc_layer layer packages file for Spacemacs.
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

;; (defun python/post-init-company ()
;;   (spacemacs|add-company-hook python-mode)
;;   (spacemacs|add-company-hook inferior-python-mode)
;;   (push '(company-files company-capf) company-backends-inferior-python-mode)
;;   (add-hook 'inferior-python-mode-hook (lambda ()
;;                                          (setq-local company-minimum-prefix-length 0)
;;                                          (setq-local company-idle-delay 0.5))))

(defconst misc_layer-packages
  '(company-mode)
)

(defun misc_layer/post-init-company ()
  (push))
