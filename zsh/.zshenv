export DOTFILES=$HOME/dotfiles
export EDITOR="emacsclient -t"
export LESS="-SRXF"

fzf_bin=$HOME/.fzf/bin
test -f $fzf_bin && export PATH=$PATH:$fzf_bin

# broken out configs
source $DOTFILES/zsh/path_setup
eb_config=$DOTFILES/zsh/eb_path_config
test -f $eb_config  && source $eb_config
