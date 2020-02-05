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
   markdown
   org
   php
   python
   python
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
