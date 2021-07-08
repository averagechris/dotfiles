;;; init.el -*- lexical-binding: t; -*-

;; This file controls what Doom modules are enabled and what order they load
;; in. Remember to run `home-manager switch` after modifying it!

;; NOTE Press 'SPC h d h' to access Doom's
;;      documentation. There you'll find a "Module Index" link where you'll find
;;      a comprehensive list of Doom's modules and what flags they support.

;; NOTE Move your cursor over a module's name (or its flags) and press 'K'
;;      to view its documentation. This works on
;;      flags as well (those symbols that start with a plus).
;;
;;      Alternatively, press 'gd' on a module to browse its
;;      directory (for easy access to its source code).

(doom! :input

       :completion
       company
       (ivy
        +fuzzy
        +icons
        +childframe
        +prescient)

       :ui
       doom
       doom-dashboard
       doom-quit
       (emoji
        +github
        +unicode)
       hl-todo
       indent-guides
       modeline
       ophints
       (popup
        +defaults)
       (treemacs
        +lsp)
       unicode
       vc-gutter
       vi-tilde-fringe
       workspaces
       zen

       :editor
       (evil
        +everywhere)
       file-templates
       fold
       ; (format +onsave)
       multiple-cursors
       snippets
       word-wrap

       :emacs
       (dired
        +icons)
       electric
       (ibuffer
        +icons)
       undo
       vc

       :term
       ;;eshell
       vterm

       :checkers
       syntax
       (spell
        +everywhere)

       :tools
       debugger
       direnv
       docker
       editorconfig
       (eval +overlay)
       gist
       (lookup
        +dictionary
        +offline)
       (lsp
        +peek)
       magit
       ;;make
       pdf
       ;;terraform

       :os
       (:if IS-MAC macos)
       tty

       :lang
       ;;common-lisp
       data              ; config/data formats
       emacs-lisp
       json
       ;; javascript
       ;;lua
       markdown
       nix
       org
       (python
        +lsp
        +poetry)
       rest
       ;;rust
       sh
       yaml

       :email
       (mu4e +gmail)

       :app
       ;;calendar
       ;;irc
       ;;(rss +org)
       ;;twitter

       :config
       (default +bindings +smartparens))