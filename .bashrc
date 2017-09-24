set -o vi

# swift repl fix - due to brew python being at the front of $PATH variable
alias swift="PATH=/usr/bin:$PATH swift"

# set mysql to the brew install path
alias mysql=/usr/local/mysql/bin/mysql
alias mysqladmin=/usr/local/mysql/bin/mysqladmin

# enable excercism cli bash completion
if [ -f ~/.config/exercism/exercism_completion.bash ]; then
	source ~/.config/exercism/exercism_completion.bash
fi

#############################
# Enable fzf cool stuffs
#############################
[ -f ~/.fzf.bash ] && source ~/.fzf.bash
# use ripgrep (default is find)
export FZF_DEFAULT_COMMAND='rg --files --no-ignore --hidden --follow -g "!{.git,node_modules}/*" 2> /dev/null'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
bind -x '"\C-p": vim $(fzf);'

_fzf_compgen_path() {
    rg -g "" "$1"
}

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
alias vim=nvim  # use neovim instead of vim

# lr is a full recursive directory listing piped to less
alias lr='ls -R | grep ":$" | sed -e '\''s/:$//'\'' -e '\''s/[^-][^\/]*\//--/g'\'' -e '\''s/^/   /'\'' -e '\''s/-/|/'\'' | less'

###################
# QUICK NAV Aliases
###################
export GOCODE=$GOPATH/src/github.com/mistahchris/

#######################
# GENERAL USE FUNCTIONS
#######################
# sets up the terminal to make working on a project easy
workon () {
    project=$1

    case $project in
        "eventbrite"*)
            cd $EBPATH
            ;;
        "fastfile"*)
            cd /Users/ccummings/eventbrite_github/triage_projects/jira_modal
            ;;
        "data_nerds"*)
            cd /Users/ccummings/mistahchris_github/data_nerds/
            pyenv activate data_nerds
            ;;
        "tableau_help"*)
            cd /Users/ccummings/tableau_help
            source ./private/config_vars.sh
            source ./.profile.d/000-react-app-exports.sh
            ;;
    esac
}
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
            *)           echo "'$1' cannot be extracted via extract()" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}

update_brew_shit() {
    brew outdated | fzf -m -n 1 --tac --header='Select formulae to upgrade with tab' | xargs brew upgrade
}

rgvim () {
    FZF_SELECTION=$( rg -Fi "$*" | fzf -0 -1 --ansi)
    if [ ! -z "$FZF_SELECTION" ]
    then
        vim "+/$*" $( echo "$FZF_SELECTION" | awk 'BEGIN { FS=":" } { printf "%s\n", $1 }' )
    fi
}

_sleep_then_restore_clipboard() {
	sleep 30
	echo "$@" | pbcopy
}

lastpass() {
	CLIPBOARD_CONTENTS=`pbpaste`
	`lpass show -cp $@ -G`  # set the lpass cli result to clipboard
	$(_sleep_then_restore_clipboard $CLIPBOARD_CONTENTS) &
}

######################
# Eventbrite FUNCTIONS
######################
waiting-room-qa() {
    eid=$1
    if [ "$eid" -eq "$eid" ] 2>/dev/null; then
        while true ; do curl http://evbqa.com/queue_rpc/get/$eid; done
    else
        echo "Try again with a valid Eventbrite Event ID"
    fi
}
