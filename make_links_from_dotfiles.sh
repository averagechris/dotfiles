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
    $dotfiles/zsh/.zshenv $HOME
    $dotfiles/zsh/.zshrc $HOME
    $dotfiles/.config $HOME/.config
" | _trim | xargs ln -fs

# link spacemacs layers and snippets if spacemacs is installed
if test -d "$HOME/.emacs.d/private"; then
    for layer_dir in $(ls "$dotfiles/spacemacs/layers/"); do
        ln -fs "$dotfiles/spacemacs/layers/$layer_dir" "$HOME/.emacs.d/private/"
    done;
    for snippet_dir in $(ls "$dotfiles/spacemacs/snippets/"); do
        ln -fs "$dotfiles/spacemacs/snippets/$snippet_dir" "$HOME/.emacs.d/private/snippets/"
    done;
fi

if test "$(uname)" = "Darwin"; then
    mydaemons=$dotfiles/start_scripts/daemons/macos
    daemon_dir=$HOME/Library/LaunchAgents
    for daemon in "$mydaemons"/*.plist; do
        ln -fs "$daemon" "$daemon_dir"
    done;
fi


# link private variables from google drive if available
eb_gdrive="$HOME/Google Drive File Stream/My Drive/config_backups"
test -d "$eb_gdrive" && \
    ln -fs "$eb_gdrive/.private_variables" "$HOME"

# link private variables from icould drive if available
icloud="$HOME/Library/Mobile Documents/com~apple~CloudDocs/config_backups"
test -d "$icloud" && \
    ln -fs "$icloud/.personal_variables" "$HOME"
