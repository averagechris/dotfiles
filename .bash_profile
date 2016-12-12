# Load .bashrc if it exists
test -f ~/.bashrc && source ~/.bashrc

# Load brew git completion and git prompt scripts
source /usr/local/Cellar/git/2.11.0/etc/bash_completion.d/git-completion.bash
source /usr/local/Cellar/git/2.11.0/etc/bash_completion.d/git-prompt.sh


################
# PATH SETTINGS
################
export GOPATH=$HOME/go_projects
export YARNPATH=`yarn global bin`
export PATH=/usr/local/bin:$GOPATH/bin:$YARNPATH:$PATH

# swift repl fix - due to brew python being at the front of $PATH variable
alias swift="PATH=/usr/bin:$PATH swift"

# set mysql to the brew install path
alias mysql=/usr/local/mysql/bin/mysql
alias mysqladmin=/usr/local/mysql/bin/mysqladmin


#####################
# GENERAL USE ALIASES
#####################
alias cp='cp -iv'  # copy a file with the verbose and warning flags
alias mv='mv -iv'  # move a file/dir with verbose and warning flags
alias mkdir='mkdir -pv'  # make directory with the path and verbose flags
alias cd..='cd ../'  # Go back 1 directory level
alias finder='open -a Finder ./'  # Open current directory in MacOS Finder
alias path='echo -e ${PATH//:/\\n}'  # Echo all executable Paths
alias numFiles='echo $(ls -1 | wc -l)'  # Count of non-hidden files in current dir
alias staticip='dig +short myip.opendns.com @resolver1.opendns.com' # get the static ip of the current network

# lr is a full recursive directory listing piped to less
alias lr='ls -R | grep ":$" | sed -e '\''s/:$//'\'' -e '\''s/[^-][^\/]*\//--/g'\'' -e '\''s/^/   /'\'' -e '\''s/-/|/'\'' | less'

###################
# QUICK NAV Aliases
###################
export GOCODE=$GOPATH/src/github.com/mistahchris/

#####################
# Eventbrite Aliases
#####################
export EBPATH='/Users/ccummings/Eb-Github/eventbrite'
export ARCANIST_INSTALL_DIR=/Users/ccummings/.evbdevtools
source $ARCANIST_INSTALL_DIR/devtools/scripts/devenv_bash/arcanist_helpers.sh

#######################
# GENERAL USE FUNCTIONS
#######################
# Always list directory contents after 'cd'
cd () {
    builtin cd "$@"; ls -a;
}

# moves a file to the macOS Trash
trash () {
    command mv "$@" ~/.Trash ;
}

# opens a file in the macOS preview
preview () {
    qlmanage -p "$*" >& /dev/null;
}

# creates a zip archive folder
zipf () {
zip -r "$1".zip "$1" ;
}

# make a directory and change into it
mcd () {
        mkdir -p $1;
        cd $1;
}

calc () {
    echo "print($@)" | python3
}

# cdfinder changes the directory to the frontmost open finder window
    cdfinder () {
        currFolderPath=$( /usr/bin/osascript <<EOT
            tell application "Finder"
                try
            set currFolder to (folder of the front window as alias)
                on error
            set currFolder to (path to desktop folder as alias)
                end try
                POSIX path of currFolder
            end tell
EOT
        )
        echo "cd to \"$currFolderPath\""
        cd "$currFolderPath"
    }

# sets the contents of a file to the macOS clipboard
copy () {
        cat $1 | pbcopy
}

# kill a process by name
die () {
    name=$1
    firstChar=${name:0:1}
    rest=${name:1:${#name}}
    pid=`ps aux | grep "[$firstChar]$rest" | awk '{print $2}'`
    kill $pid
}

# extracts the git branch name
parseBranch() {
    git branch | grep "^\* " | sed "s/\* //g"
}

# pullall iterates through each immediate child directory, if it's a git repo
# switches to master branch, runs: git pull
# switches back to whatever branch it was originally
pullall () {
        dir=`pwd`
        echo "Begin pulling new master branch code for every child repo..."
        echo "..."
        for REPO in `ls -l | grep ^d | grep -oE '[^ ]+$'`;
            do
                echo "----------------------------"
                echo ""

                command -p cd "$REPO";
                if [ -d ".git" ]; then
                        cbranch=`parseBranch`

                    if [ $cbranch != "master" ]; then
                        command git checkout "master"
                    fi

                    echo "pulling master branch of: $REPO ..."
                    command git pull

                    if [ $cbranch != "master" ]; then
                        command -p cd "$cbranch"
                    fi
                fi
                command -p cd $dir
        done;
}


# useful for extracting compressed folders
extract () {
    if [ -f $1 ] ; then
      case $1 in
        *.tar.bz2)   tar xjf $1     ;;
        *.tar.gz)    tar xzf $1     ;;
        *.bz2)       bunzip2 $1     ;;
        *.rar)       unrar e $1     ;;
        *.gz)        gunzip $1      ;;
        *.tar)       tar xf $1      ;;
        *.tbz2)      tar xjf $1     ;;
        *.tgz)       tar xzf $1     ;;
        *.zip)       unzip $1       ;;
        *.Z)         uncompress $1  ;;
        *.7z)        7z x $1        ;;
        *)     echo "'$1' cannot be extracted via extract()" ;;
         esac
     else
         echo "'$1' is not a valid file"
     fi
}


#############################
# IMPRTANT STUFF TO LOAD LAST
#############################
export CLICOLOR=1  # enable colors

# terminal prompt
PS1='----------\n\u @ \[\033[0;35m\]\h\[\033[0m\]\n|   \[\033[1;34m\]\w\[\033[0;32m\]$(__git_ps1)\[\033[0m\]\n└─ $ '

# set vi mode
set -o vi

# to make sure global python packages are only installed intentionally, limit pip to running only in venv
export PIP_REQUIRE_VIRTUALENV=true
