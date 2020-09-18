# Path to your oh-my-zsh installation.
export ZSH=$HOME/.oh-my-zsh

# Set name of the theme to load. Optionally, if you set this to "random"
# it'll load a random theme each time that oh-my-zsh is loaded.
# See https://github.com/robbyrussell/oh-my-zsh/wiki/Themes
ZSH_THEME="bira"

# Set list of themes to load
# Setting this variable when ZSH_THEME=random
# cause zsh load theme from this variable instead of
# looking in ~/.oh-my-zsh/themes/
# An empty array have no effect
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

DISABLE_UNTRACKED_FILES_DIRTY="true"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(
    git
    poetry
    pyenv
    ruby
)

source $ZSH/oh-my-zsh.sh

# User configuration
export LANG=en_US.UTF-8

# vi mode config
bindkey -v
export KEYTIMEOUT=1

# lazy load functions defined in dotfiles/zsh/functions
my_funcs=$DOTFILES/zsh/functions
fpath=($my_funcs $fpath)
for func in $(ls $my_funcs); do autoload $func; done;

# broken out configs
source $DOTFILES/zsh/general_aliases
test -f $HOME/.zfunc && fpath+=~/.zfunc
test -f ~/.fzf.zsh && source ~/.fzf.zsh  # this is here cause fzf looks here on install
source $DOTFILES/zsh/fzf_config
source $DOTFILES/zsh/os_specific_config
source $DOTFILES/zsh/eb_specific_config

###################################
# below here are things appended to
# automatically by various tools
###################################

if which pyenv-virtualenv-init > /dev/null; then eval "$(pyenv virtualenv-init -)"; fi

# pip zsh completion start
function _pip_completion {
  local words cword
  read -Ac words
  read -cn cword
  reply=( $( COMP_WORDS="$words[*]" \
             COMP_CWORD=$(( cword-1 )) \
             PIP_AUTO_COMPLETE=1 $words[1] ) )
}
compctl -K _pip_completion pip
# pip zsh completion end
