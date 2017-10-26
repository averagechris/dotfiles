set PYTHON_2_PATH $HOME/.pyenv/versions/misc2/bin
set PYTHON_3_PATH $HOME/.pyenv/versions/misc3/bin
set RUSTPATH $HOME/.cargo/bin
set -x PATH $RUSTPATH $PYTHON_2_PATH $PYTHON_3_PATH $PATH
set FZF_DEFAULT_COMMAND 'rg --files --hidden --follow'

fish_vi_key_bindings
alias vim nvim
