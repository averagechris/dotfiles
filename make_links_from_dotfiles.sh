#!/bin/bash

dotfiles="$HOME/dotfiles"

# symbolic links
echo -n "$dotfiles/.profile $HOME
$dotfiles/.tmux.conf $HOME
$dotfiles/.vimrc $HOME
$dotfiles/bash/.bash_profile $HOME
$dotfiles/bash/.bashrc $HOME
$dotfiles/spacemacs/.spacemacs $HOME
$dotfiles/zsh/.zshrc $HOME" | xargs ln -fs

# link spacemacs snippets if spacemacs is installed
[ -d ~/.emacs.d/private ] && ln -fs $dotfiles/spacemacs/snippets ~/.emacs.d/private/snippets

# link nvim config if nvim is installed
[ -d ~/.config ] && which nvim &> /dev/null && ln -fs $dotfiles/nvim "$HOME/.config"
