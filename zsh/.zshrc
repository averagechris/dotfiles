# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

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

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion. Case
# sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment the following line to disable bi-weekly auto-update checks.
# DISABLE_AUTO_UPDATE="true"

# Uncomment the following line to change how often to auto-update (in days).
# export UPDATE_ZSH_DAYS=13

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(
  git
  pyenv
  tmux
)

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

export LANG=en_US.UTF-8

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
export DOTFILES=$HOME/dotfiles
export PYENV_ROOT=$HOME/.pyenv
export PYTHON_2_PATH=$PYENV_ROOT/versions/misc2/bin
export PYTHON_3_PATH=$PYENV_ROOT/versions/misc3/bin
PYENV_SHIMS=/Users/ccummings/.pyenv/shims
PYENV_VENV_SHIMS=/usr/local/Cellar/pyenv-virtualenv/1.1.1/shims
PATH=$PYENV_ROOT/bin:$PYENV_ROOT/shims:$DOTFILES/bin:/usr/local/bin:$PYENV_VENVSHIMS:$PYENV_SHIMS:$HOME/.fzf/bin:$PYTHON_2_PATH:$PYTHON_3_PATH:$PATH

if [ -d $HOME/.cargo/bin ]; then
    export RUSTPATH=$HOME/.cargo/bin
    export RUST_SRC_PATH=$HOME/.multirust/toolchains/stable-x86_64-apple-darwin/lib/rustlib/src/rust/src
    PATH=$PATH:$RUSTPATH
	test -f $HOME/.zfunc && fpath+=~/.zfunc
fi

if [ -d "$HOME/eventbrite" ]; then
    export EVENTBRITE="$HOME/eventbrite"
    export ARCANIST_INSTALL_DIR="$HOME/.evbdevtools"
    export ARCANIST_BIN="$ARCANIST_INSTALL_DIR/arcanist/bin"
    export ARCANISTHELPERS="$ARCANIST_INSTALL_DIR/devtools/scripts/devenv_bash/arcanist_helpers.sh"
	  export BAY_HOME="$EVENTBRITE/docker-dev"
	  export DM_START="$ARCANIST_INSTALL_DIR/devtools/scripts/install_devenv/dm_start.sh"

	  [ -f $ARCANISTHELPERS ] && source $ARCANISTHELPERS
	  [ -f $DM_START ] && source $DM_START
    PATH="$PATH:$ARCANIST_BIN"

    source "$HOME/.private_variables"
    EB_FUNCTIONS=$DOTFILES/zsh/eb_functions
    fpath=($EB_FUNCTIONS $fpath)
    for func in $(ls $EB_FUNCTIONS); do autoload $func; done;

    source $DOTFILES/zsh/ebaliases.sh

    # at EB we run black on python 2 code bases, so I need an alias for black
    # TODO: probably don't need this anymore cause pyenv kicks ass
    # alias black=$PYENV_ROOT/versions/misc3/bin/black
fi

MY_ZSH_FUNCTIONS=$DOTFILES/zsh/functions
fpath=($MY_ZSH_FUNCTIONS $fpath)
for func in $(ls $MY_ZSH_FUNCTIONS); do autoload $func; done;

alias edit='emacsclient -t -a vim'
export EDITOR=vim

# less pager config
export LESS="-SRXF"

set -o vi
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

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