(configuration-layer/declare-layers
 '(
   ansible
   better-defaults
   common-lisp
   csv
   emacs-lisp
   emoji
   git
   gtags
   helm
   html
   javascript
   (lsp :variables
        lsp-rust-server 'rust-analyzer)
   markdown
   org
   php
   (python :variables
           python-backend 'lsp
           python-formatter 'black)
   react
   (ruby :variables
         ruby-version-manager 'rbenv)
   ruby-on-rails
   rust
   shell
   shell-scripts
   spell-checking
   sql
   syntax-checking
   version-control
   vimscript
   yaml
   (auto-completion :variables
                    auto-completion-enable-sort-by-usage t
                    auto-completion-enable-snippets-in-popup t)))
