set -x DOTFILES ~/dotfiles
set -x PYENV_ROOT $HOME/.pyenv
set -x WORKON_HOME $PYENV_ROOT/versions/
set -x PYENV_SHELL fish
set -x PYTHON_2_PATH $PYENV_ROOT/versions/misc2/bin
set -x PYTHON_3_PATH $PYENV_ROOT/versions/misc3/bin
set -x RUSTPATH $HOME/.cargo/bin

set -x PATH $RUSTPATH $PYTHON_2_PATH $PYTHON_3_PATH $PYENV_ROOT/bin $PYENV_ROOT/shims $HOME/.local/bin $DOTFILES/bin /usr/local/bin $PATH


set -x FZF_DEFAULT_COMMAND 'fd --type f --follow --hidden --exclude .git'
set -x FZF_CTRL_T_COMMAND $FZF_DEFAULT_COMMAND

set -l ALLOW_VI_IN_TERM 'xterm-256color' 'screen-256color'
if contains $TERM $ALLOW_VI_IN_TERM
  fish_vi_key_bindings
end

set -x EVENTBRITE ~/eventbrite_github/eventbrite
set -x BAY_HOME $EVENTBRITE/docker-dev

# source other misc variables if exist
set -x MISC_VARIABLES_FILE "$DOTFILES/fish/misc_variables.fish"
test -e "$MISC_VARIABLES_FILE"; and source $MISC_VARIABLES_FILE

# source private variables if exist
set -x PRIVATE_VARIABLES_FILE "$DOTFILES/fish/private_variables.fish"
test -e "$PRIVATE_VARIABLES_FILE"; and source $PRIVATE_VARIABLES_FILE

set -x EDITOR emacsclient -c
