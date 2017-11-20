set -x PYENV_ROOT $HOME/.pyenv
set -x PYENV_SHELL fish
set -x PYTHON_2_PATH $PYENV_ROOT/versions/misc2/bin
set -x PYTHON_3_PATH $PYENV_ROOT/versions/misc3/bin
set -x RUSTPATH $HOME/.cargo/bin

set -x PATH $RUSTPATH $PYTHON_2_PATH $PYTHON_3_PATH $PYENV_ROOT/bin $PYENV_ROOT/shims $PATH


set -x FZF_DEFAULT_COMMAND 'fd --type f --follow --hidden --exclude .git'
set -x FZF_CTRL_T_COMMAND $FZF_DEFAULT_COMMAND

fish_vi_key_bindings
alias vim nvim
