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
    anaconda-mode
    docker-tramp
    git-commit
    git-gutter+
    helm-ag
    prettier-js
    python
    seq
    smtpmail-multi
    web-mode
    yasnippet
    yasnippet-snippets
    (blacken :location (recipe
                        :fetcher github
                        :repo "proofit404/blacken"))
   ))

;;;;;;;;;;;;;;;;;;;;;;;;
;; inits for ownership
;;;;;;;;;;;;;;;;;;;;;;;;
(defun personal-layer/init-blacken ()
  "Own blacken package."
  ;; (use-package blacken :defer t)
  )

(defun personal-layer/init-docker-tramp ()
  "Own docker-tramp package."
  (use-package docker-tramp :defer t))

(defun personal-layer/init-prettier-js ()
  "Own prettier-js package."
  (use-package prettier-js :defer t))

(defun personal-layer/init-seq ()
  "Own seq package."
  (use-package seq :defer t))

(defun personal-layer/init-smtpmail-multi ()
  "Own smtpmail-multi package."
  (use-package smtpmail-multi :defer t))

(defun personal-layer/init-yasnippet-snippets ()
  "Own yasnippet-snippets package."
  (use-package yasnippet-snippets :defer t))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; post inits for configuration of any packages
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun personal-layer/post-init-anaconda-mode ()
  "Configure anaconda-mode."
  (setq anaconda-mode-localhost-address "localhost"))

(defun personal-layer/post-init-blacken ()
  "Configure blacken."
  (define-minor-mode blacken-mode
    "Optionally run black before saving."
    :lighter " Black"
    (if blacken-mode
        (add-hook 'before-save-hook 'personal-layer-maybe-format-buffer-with-black nil t)
      (remove-hook 'before-save-hook 'personal-layer-maybe-format-buffer-with-black t))))

(defun personal-layer/post-init-python ()
  "Configure python."
  (progn
    ;; use black instead of yapf
    (spacemacs|use-package-add-hook python
      :post-config
      (spacemacs/set-leader-keys-for-major-mode 'python-mode
        "=" 'blacken-buffer))
    (add-hook 'python-mode-hook 'blacken-mode)

    ;; override python breakpoint function, copy pasted from python layer's funcs.el
    (defun spacemacs/python-toggle-breakpoint ()
      "Personally customized: Add a break point, highlight it."
      (interactive)
      (let ((trace (cond ((spacemacs/pyenv-executable-find "wdb") "import wdb; wdb.set_trace()")
                         ((spacemacs/pyenv-executable-find "ipdb")
                          "import ipdb; ipdb.set_trace(context=15)")
                         ((spacemacs/pyenv-executable-find "pudb") "import pudb; pudb.set_trace()")
                         ((spacemacs/pyenv-executable-find "ipdb3") "import ipdb; ipdb.set_trace()")
                         ((spacemacs/pyenv-executable-find "pudb3") "import pudb; pudb.set_trace()")
                         (t "import pdb; pdb.set_trace()")))
            (line (thing-at-point 'line)))
        (if (and line (string-match trace line))
            (kill-whole-line)
          (progn
            (back-to-indentation)
            (insert trace)
            (insert "\n")
            (python-indent-line)))))
  ))

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

(defun personal-layer/post-init-yasnippet ()
  "Configure yasnippet."
  ;; add snippet dirs not in VCS to yas-snippet-dirs
  (progn
    (setq
    yas-snippet-dirs
    (append yas-snippet-dirs
            (seq-filter
              'file-directory-p
              '("~/Google Drive File Stream/My Drive/config_backups/snippets"
                "~/Library/Mobile Documents/com~apple~CloudDocs/config_backups/snippets"))))
    ;; TODO: could this be moved somewhere earlier in the init process
    ;; so that we don't have to call `yas-reload-all`?
    (yas-reload-all)))

(defun personal-layer/post-init-yassnippet-snippets ()
  "Configure yasnippet-snippets."
  (append yas-snippet-dirs yassnippet-snippets-dir))

;;; packages.el ends here
