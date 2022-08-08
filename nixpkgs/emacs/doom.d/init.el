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

(doom! :completion
       (company +childframe)
       (ivy +fuzzy
            +icons
            +childframe
            +prescient)

       :ui
       doom
       doom-dashboard
       doom-quit
       (emoji +unicode)
       hl-todo
       indent-guides
       modeline
       ophints
       navflash
       (popup +all
              +defaults)
       (treemacs +lsp)
       unicode
       vc-gutter
       vi-tilde-fringe
       workspaces
       zen

       :editor
       (evil +everywhere)
       fold
       (format +onsave)
       multiple-cursors
       ;; snippets
       word-wrap

       :emacs
       (dired +icons)
       electric
       (ibuffer +icons)
       undo
       vc

       :term
       vterm

       :checkers
       (syntax +childframe)
       (spell +everywhere)

       :tools
       ;; debugger
       direnv
       (docker +lsp)
       editorconfig
       (eval +overlay)
       (lookup +dictionary
               +offline)
       (lsp +peek)
       magit
       pdf
       tree-sitter

       :os
       (:if IS-MAC macos)
       (tty +osc)

       :lang
       data
       emacs-lisp
       json
       (markdown +grip)
       nix
       (python +lsp
               +pyright
               +tree-sitter)
       (rust +lsp)
       (sh +lsp)
       (yaml +lsp)

       :email
       mu4e

       :config
       (default +bindings +smartparens))
