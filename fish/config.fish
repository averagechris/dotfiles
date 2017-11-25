set -x PYENV_ROOT $HOME/.pyenv
set -x WORKON_HOME $PYENV_ROOT/versions/
set -x PYENV_SHELL fish
set -x PYTHON_2_PATH $PYENV_ROOT/versions/misc2/bin
set -x PYTHON_3_PATH $PYENV_ROOT/versions/misc3/bin
set -x RUSTPATH $HOME/.cargo/bin

set -x PATH $RUSTPATH $PYTHON_2_PATH $PYTHON_3_PATH $PYENV_ROOT/bin $PYENV_ROOT/shims $HOME/.local/bin $PATH


set -x FZF_DEFAULT_COMMAND 'fd --type f --follow --hidden --exclude .git'
set -x FZF_CTRL_T_COMMAND $FZF_DEFAULT_COMMAND

if test "$TERM" != 'dumb'
  fish_vi_key_bindings
end

alias vim nvim
