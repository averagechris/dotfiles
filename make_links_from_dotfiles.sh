#!/bin/bash

dotfiles="$HOME/dotfiles"

function _trim {
    # remove blank lines, leading and trailing whitespace
    sed '/^$/d' | sed -e 's/^ *//' | sed -e 's/ *$//'
}

# symbolic links
echo -n "
    $dotfiles/.myclirc $HOME
    $dotfiles/.profile $HOME
    $dotfiles/.tmux.conf $HOME
    $dotfiles/.vimrc $HOME
    $dotfiles/bash/.bash_profile $HOME
    $dotfiles/bash/.bashrc $HOME
    $dotfiles/spacemacs/.spacemacs $HOME
    $dotfiles/zsh/.zshenv $HOME
    $dotfiles/zsh/.zshrc $HOME
" | _trim | xargs ln -fs

# link spacemacs layers and snippets if spacemacs is installed
if test -d $HOME/.emacs.d/private; then
    for layer_dir in `ls $dotfiles/spacemacs/layers/`; do
        ln -fs $dotfiles/spacemacs/layers/$layer_dir $HOME/.emacs.d/private/
    done
    ln -fs $dotfiles/spacemacs/snippets $HOME/.emacs.d/private/
fi

# link nvim config if nvim is installed
test -d $HOME/.config -a `which nvim 2> /dev/null` != "" && \
    ln -fs $dotfiles/nvim "$HOME/.config"

if test `uname` = "Darwin"; then
    mydaemons=$dotfiles/start_scripts/daemons/macos
    daemon_dir=$HOME/Library/LaunchAgents
    for daemon in $mydaemons/*.plist; do
        ln -fs "$mydamons/$daemon" $daemon_dir
    done;
fi
