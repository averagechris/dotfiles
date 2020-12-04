#! /bin/bash

stderr_log=/tmp/install_important_packages_errors.log
stdout_log=/tmp/install_important_packages.log

function _trim {
    # remove blank lines, leading and trailing whitespace
    sed '/^$/d' | sed -e 's/^ *//' | sed -e 's/ *$//'
}

function _filter_known_ok {
    # filter out log messages known to be ok
    _trim < $1 | \

        # brew related filters
        grep -v "brew upgrade " | \
        grep -v "already installed" | \
        egrep -iv "re-?install" | \
        grep -v "It seems there is already an App at" \

        # rustup related filters
        egrep -v "info: (latest)|(downloading)|(installing)|(default)"
}

function install_everything {
    ###################
    # install homebrew
    ###################
    which brew &> /dev/null || \
        /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"

    # NOTE: don't try to be smart with OS, let brew decide what it can and can't install

    ###################
    # install packages
    ###################
    echo -n '
    coreutils
    curl
    fd
    fish
    fzf
    go
    ispell
    lastpass-cli
    moreutils
    mycli
    mysql
    neovim
    node
    openssl
    ripgrep
    socat
    sd
    terminal-notifier
    the_silver_searcher
    tmux
    wget
    zsh
    koekeishiya/formulae/skhd
    koekeishiya/formulae/yabai
    ' | _trim | xargs brew install


    ############################
    # install gui and cask apps
    ############################
    echo -n '
    docker
    firefox
    flux
    flycut
    spectacle
    karabiner-elements
    ' | _trim | xargs brew cask install


    #################################
    # install apps from special taps
    #################################
    brew list | grep -q emacs-plus || {
        brew tap d12frosted/emacs-plus && brew install emacs-plus
    }


    ####################
    # install oh-my-zsh
    ####################
    test -d $HOME/.oh-my-zsh || \
        sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"

    ####################
    # install spacemacs
    ####################
    emacs_d=$HOME/.emacs.d
    test -d $emacs_d || \
        git clone https://github.com/syl20bnr/spacemacs $emacs_d

    ######################################
    # install vim-plug for vim and neovim
    ######################################
    vim_plug_file=$HOME/.vim/autoload/plug.vim
    test -f $vim_plug_file || \
        curl -fLo $vim_plug_file --create-dirs \
             https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

    nvim_plug_file=$HOME/.local/share/nvim/site/autoload/plug.vim
    test -f $nvim_plug_file || \
        curl -fLo $nvim_plug_file --create-dirs \
             https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

    ################
    # install pyenv
    ################
    test -d $HOME/.pyenv || \
        curl https://pyenv.run | bash

    #################
    # install rustup
    #################
    which rustup &> /dev/null || \
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
}

function on_success {
    if test $(
        _filter_known_ok $stderr_log | wc -l
    ) -eq 0; then
        echo "Install completed without error."
        rm $stderr_log
        rm $stdout_log
        return 0
    else
        echo "Install completed but errors were logged."
        echo "See full stderr at $stderr_log"
        echo "See full stdout at $stdout_log"
        return 1
    fi
}

function on_error {
    echo "Install did not complete or partially completed with unhandled error."
    echo "See full stderr at $stderr_log"
    echo "See full stdout at $stdout_log"
    return 2
}

# you can redirect stderr like this if you want to more easily debug:
#     2> >(tee -a $stderr_log >&2)

install_everything \
    > $stdout_log \
    2> $stderr_log \
    && on_success \
    || on_error
