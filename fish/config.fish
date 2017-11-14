set -x PYTHON_2_PATH $HOME/.pyenv/versions/misc2/bin
set -x PYTHON_3_PATH $HOME/.pyenv/versions/misc3/bin
set -x RUSTPATH $HOME/.cargo/bin
set -x PATH $RUSTPATH $PYTHON_2_PATH $PYTHON_3_PATH $PATH
set -x PYENV_ROOT $HOME/.pyenv
set -x FZF_DEFAULT_COMMAND 'rg --files --hidden --follow'

fish_vi_key_bindings
alias vim nvim
