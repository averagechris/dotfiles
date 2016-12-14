# this is pretty old and is prob worthless at this point

# set vi mode by default
set -o vi

# pip should only run if there is a virtualenv currently activated
export PIP_REQUIRE_VIRTUALENV=true


###########
# Functions
###########

# make a directory and change into it
mcd () {
        mkdir -p $1
        cd $1
}

# set the contents of a file to the mac os
# clipboard
copy () {
        cat $1 | pbcopy
}

# iterate through each immediate child directory
# check to see if it's a git repo and run -- git pull
pullall () {
        dir=`pwd`
        for REPO in `ls -l | grep ^d | grep -oE '[^ ]+$'`;
            do
                command -p cd "$REPO";
                if [ -d ".git" ]; then
                    cbranch=`git branch | grep "^\* " | sed "s/\* //g"`

                    if [ $cbranch != "master" ]; then
                        echo "checking out master branch..."
                        command git checkout "master"
                    fi

                    echo "pulling master branch of: $REPO ..."
                    command git pull


                    if [ $cbranch != "master" ]; then
                        echo "switching back to branch: $cbranch ..."
                        command -p cd "$cbranch"
                    fi

                    echo "done pulling $REPO ..."
                    echo ""  #hacky way of newlining
                fi
                command -p cd $dir
        done;
}


###################
# ALIASES for EB VM
###################
alias mysql-core='mysql -u root -h 127.0.0.1 -P `docker port mysql-core 3306 | cut -f 2 -d :`'
alias mysql-payments='mysql -u root -h 127.0.0.1 -P `docker port mysql-payments 3306 | cut -f 2 -d :`'
alias mysql-webhooks='mysql -u root -h 127.0.0.1 -P `docker port mysql-webhooks 3306 | cut -f 2 -d :`'

