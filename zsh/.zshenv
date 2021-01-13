export DOTFILES=$HOME/dotfiles
export EDITOR="emacsclient -t"
export LESS="-SRXF"
export WORKON_HOME=$HOME/.local/share/virtualenvs/

fzf_bin=$HOME/.fzf/bin
test -f $fzf_bin && export PATH=$PATH:$fzf_bin

# broken out configs
source $DOTFILES/zsh/path_setup
