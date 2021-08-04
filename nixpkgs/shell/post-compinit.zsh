function () {
    for functions_group in $(ls $HOME/dotfiles/nixpkgs/shell/zsh_functions)
    do
        if [[ $functions_group =~ "macos" && $(uname) != "Darwin" ]]
        then
            continue
        fi

        full_path="$HOME/dotfiles/nixpkgs/shell/zsh_functions/$functions_group/"
        fpath=("$full_path" $fpath)

        for fn in $(ls "$full_path")
        do
            autoload $fn
        done
    done
}

eval "$(direnv hook zsh)"
PATH=$HOME/.poetry/bin:$PATH
