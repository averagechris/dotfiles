# TODO ctrl p isn't working
zle -N fzf_ctrl_p edit_fzf && bindkey '^p' fzf_ctrl_p

function () {
    # anonymous functions are evaluated without being called
    # # so we're just using this to scope our variables

    # lazy load functions defined in dotfiles/zsh/functions
    local fns=$HOME/dotfiles/zsh/functions
    local sure=$HOME/dotfiles/zsh/sure

    fpath=($sure $fns $fpath)
    for fn in $(ls $fns); do autoload $fn; done;
    [[ -d $sure ]] && for fn in $(ls $sure); do autoload $fn; done;
}

eval "$(direnv hook zsh)"
PATH=$HOME/.poetry/bin:$PATH
