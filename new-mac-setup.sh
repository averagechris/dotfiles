getbrew () {
    which -s brew
    if [[ $? != 0 ]] ; then
        echo "homebrew isn't installed."
        echo "installing homebrew..."
        /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    else
        echo "updating homebrew"
        brew update
    fi
}

install_all_languages () {
    install_python2
    install_python3
    install_go
    install_java
    install_node
}


install_basics () {
    echo "sweet, a new machine! installing the basics..."
    getbrew
    which -s git || brew install git
    brew install vim
    brew install tmux
    brew install the_silver_searcher
}
