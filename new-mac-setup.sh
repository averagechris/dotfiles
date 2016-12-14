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

install_languages () {
    brew install python
    brew install python3
    brew install go
    brew install java
    brew install node
    brew install swift
}

getDotfiles () {
    dir=`pwd`
    mkdir -p ~/dotfiles
    git clone https://github.com/mistahchris/dotfiles.git ~/dotfiles

    # create a symlink for .vimrc and .bash_profile in ~
    ln -s ~/dotfiles/.bash_profile ~/.bash_profile
    ln -s ~/dotfiles.vimrc ~/.vimrc
}


install_basics () {

    echo "sweet, a new machine! installing the basics..."
    getbrew
    which -s git || brew install git
    brew install vim
    brew install tmux
    brew install the_silver_searcher

    echo "getting your config files from github"
    getDotfiles
}

install_apps () {
    brew cask install google-chrome
    brew cask install iterm2
    brew cask install lastpass
    brew cask install spectacle
    brew cask install slack
    brew cask install atom
    brew cask install evernote
}
