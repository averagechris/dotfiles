function () {
    # anonymous functions are evaluated without being called
    # # so we're just using this to scope our variables

    # lazy load functions defined in dotfiles/zsh/functions
    local fns=$HOME/dotfiles/zsh/functions
    local sure=$HOME/dotfiles/zsh/sure
    local macosfns=$HOME/dotfiles/zsh/macos_functions

    fpath=($sure $fns $fpath)
    for fn in $(ls $fns); do autoload $fn; done;
    [[ -d $sure ]] && for fn in $(ls $sure); do autoload $fn; done;

    if test $(uname) = "Darwin"; then
        fpath=($fpath $macosfns)
        [[ -d $macosfns ]] && for fn in $(ls $macosfns); do autoload $fn; done;
    fi
}

eval "$(direnv hook zsh)"
PATH=$HOME/.poetry/bin:$PATH
