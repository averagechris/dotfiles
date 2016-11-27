# prompt settings
export PS1="[\W] $ "

# color settings
export CLICOLOR=1
export LSCOLORS=ExFxBxDxCxegedabagacad

# arc tools env variables
export EBPATH=/Users/ccummings/Eb-Github/eventbrite/

# Set architecture flags
export ARCHFLAGS="-arch x86_64"

### PATH SETTINGS
# add GOPATH env variable for golang
export GOPATH=$HOME/go_projects
# export PATH=$ARCANIST_INSTALL_DIR/bin:/usr/local/bin:$GOPATH/bin:$PATH
export PATH=/usr/local/bin:$GOPATH/bin:$PATH
###
# Load .bashrc if it exists
test -f ~/.bashrc && source ~/.bashrc

# swift repl fix - due to brew python being at the front of $PATH variable
alias swift="PATH=/usr/bin:$PATH swift"

# mysql stuff
alias mysql=/usr/local/mysql/bin/mysql
alias mysqladmin=/usr/local/mysql/bin/mysqladmin
# end mysql stuff

alias cp='cp -iv' # preferred cp implementation
alias mv='mv -iv' # preferred mv implementation
alias mkdir='mkdir -pv' # preferred mkdir implementation
alias ll='ls -FGlAhp' # preferred less implementation
cd() { builtin cd "$@"; ls -a; } # Always list directory contents after 'cd'
alias cd..='cd ../'                         # Go back 1 directory level (for fast typers)
alias ..='cd ../'                           # Go back 1 directory level
alias .2='cd ../../'                        # Go back 2 directory levels
alias .3='cd ../../../'                     # Go back 3 directory levels
alias .4='cd ../../../../'                  # Go back 4 directory levels
alias .5='cd ../../../../../'               # Go back 5 directory levels
alias finder='open -a Finder ./'            # finder:            Opens current directory in MacOS Finder
alias ~="cd ~"                              # ~:            Go Home
# alias c='clear'                           # c:            Clear terminal display
# alias which='type -all'                   # which:        Find executables
alias path='echo -e ${PATH//:/\\n}'         # path:         Echo all executable Paths
alias show_options='shopt'                  # Show_options: display bash options settings
alias fix_stty='stty sane'                  # fix_stty:     Restore terminal settings when screwed up
alias cic='set completion-ignore-case On'   # cic:          Make tab-completion case-insensitive
mkdircd () { mkdir -p "$1" && cd "$1"; }    # mcd:          Makes new Dir and jumps inside
trash () { command mv "$@" ~/.Trash ; }     # trash:        Moves a file to the MacOS trash
preview () { qlmanage -p "$*" >& /dev/null; }    # ql:           Opens any file in MacOS Quicklook Preview
alias DT='tee ~/Desktop/terminalOut.txt'    # DT:           Pipe content to file on MacOS Desktop
alias edit='atom' # edit file with Atom text editor


#   lr:  Full Recursive Directory Listing
#   ------------------------------------------
alias lr='ls -R | grep ":$" | sed -e '\''s/:$//'\'' -e '\''s/[^-][^\/]*\//--/g'\'' -e '\''s/^/   /'\'' -e '\''s/-/|/'\'' | less'

#   -------------------------------
#   3.  FILE AND FOLDER MANAGEMENT
#   -------------------------------
zipf () { zip -r "$1".zip "$1" ; }          # zipf:         To create a ZIP archive of a folder
alias numFiles='echo $(ls -1 | wc -l)'      # numFiles:     Count of non-hidden files in current dir
alias make1mb='mkfile 1m ./1MB.dat'         # make1mb:      Creates a file of 1mb size (all zeros)
alias make5mb='mkfile 5m ./5MB.dat'         # make5mb:      Creates a file of 5mb size (all zeros)
alias make10mb='mkfile 10m ./10MB.dat'      # make10mb:     Creates a file of 10mb size (all zeros)

#   cdfinder:  'Cd's to frontmost window of MacOS Finder
#   ------------------------------------------------------
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

#   extract:  Extract most know archives with one command
#   ---------------------------------------------------------
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

alias getstaticip='dig +short myip.opendns.com @resolver1.opendns.com' # get the static ip of the current network

export ARCANIST_INSTALL_DIR=/Users/ccummings/.evbdevtools
source $ARCANIST_INSTALL_DIR/devtools/scripts/devenv_bash/arcanist_helpers.sh

