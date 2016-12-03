# Load .bashrc if it exists
test -f ~/.bashrc && source ~/.bashrc

# set vi mode by default
set -o vi

# terminal prompt
export PS1="[\W] $ "

# enable colors
export CLICOLOR=1

# to make sure global python packages are only installed intentionally, limit pip to running only in venv
export PIP_REQUIRE_VIRTUALENV=true

################
# PATH SETTINGS
################
export GOPATH=$HOME/go_projects
export PATH=/usr/local/bin:$GOPATH/bin:$PATH

# swift repl fix - due to brew python being at the front of $PATH variable
alias swift="PATH=/usr/bin:$PATH swift"

# set mysql to the brew install path
alias mysql=/usr/local/mysql/bin/mysql
alias mysqladmin=/usr/local/mysql/bin/mysqladmin

##############################
# GENERAL USE ALIASES
##############################
alias cp='cp -iv' # copy a file with the verbose and warning flags
alias mv='mv -iv' # move a file/dir with verbose and warning flags
alias mkdir='mkdir -pv' # make directory with the path and verbose flags
alias cd..='cd ../'                         # Go back 1 directory level (for fast typers)
alias finder='open -a Finder ./'            # finder:            Opens current directory in MacOS Finder
alias path='echo -e ${PATH//:/\\n}'         # path:         Echo all executable Paths
alias lr='ls -R | grep ":$" | sed -e '\''s/:$//'\'' -e '\''s/[^-][^\/]*\//--/g'\'' -e '\''s/^/   /'\'' -e '\''s/-/|/'\'' | less' #   lr:  Full Recursive Directory Listing
alias staticip='dig +short myip.opendns.com @resolver1.opendns.com' # get the static ip of the current network
alias numFiles='echo $(ls -1 | wc -l)'      # numFiles:     Count of non-hidden files in current dir

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

# pullall iterates through each immediate child directory, if it's a git repo
# switches to master branch, runs: git pull
# switches back to whatever branch it was originally
pullall () {
        dir=`pwd`
        for REPO in `ls -l | grep ^d | grep -oE '[^ ]+$'`;
            do
                command -p cd "$REPO";
                if [ -d ".git" ]; then
                    cbranch=`git branch | grep "^\* " | sed "s/\* //g"`

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
