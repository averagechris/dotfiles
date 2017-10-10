test -f ~/.bashrc && . ~/.bashrc
export CLICOLOR=1  # enable colors

# Load brew git completion and git prompt scripts
if [ -d "/usr/local/Cellar/git/2.13.3" ]; then
	source /usr/local/Cellar/git/2.13.3/etc/bash_completion.d/git-completion.bash
	source /usr/local/Cellar/git/2.13.3/etc/bash_completion.d/git-prompt.sh
else
	echo brew git not installed at expected location, to install it, run: brew install git
fi

export EDITOR=`which nvim`

################
# PATH SETTINGS
################
export GOPATH=$HOME/go_projects
<<<<<<< Updated upstream
export YARNPATH=/usr/local/bin
# export YARNPATH=`yarn global bin`
=======
>>>>>>> Stashed changes
export RUSTPATH=$HOME/.cargo/bin
export PATH=/usr/local/bin:$GOPATH/bin:$RUSTPATH:$PATH
export RUST_SRC_PATH=$HOME/.multirust/toolchains/stable-x86_64-apple-darwin/lib/rustlib/src/rust/src

#####################
# Eventbrite Stuff
#####################
if [ -d "$HOME/eventbrite_github" ]; then
	export EBPATH=~/eventbrite_github/eventbrite
	export ARCANIST_INSTALL_DIR=/Users/ccummings/.evbdevtools
	export ARCANISTHELPERS=~/.evbdevtools/devtools/scripts/devenv_bash/arcanist_helpers.sh
	test -f $ARCANISTHELPERS && source $ARCANISTHELPERS
	export BAY_HOME=/Users/ccummings/eventbrite_github/eventbrite/docker-dev
	export DM_START=/Users/ccummings/.evbdevtools/devtools/scripts/install_devenv/dm_start.sh
	source $DM_START
fi

#############################
# IMPRTANT STUFF TO LOAD LAST
#############################

# to make sure global python packages are only installed intentionally, limit pip to running only in venv
export PIP_REQUIRE_VIRTUALENV=true
# auto-activate pyvenv python versions when entering that dir
export PYENV_ROOT=$HOME/.pyenv
export PYENV_VIRTUALENV_DISABLE_PROMPT=1
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

# terminal prompt
PS1='  \u @ \[\033[0;35m\]\h\[\033[0m\]\n|   \[\033[1;34m\]\w\[\033[0;32m\]$(__git_ps1)\[\033[0m\]\n└─ $ '
