# TODO ctrl p isn't working
zle -N fzf_ctrl_p edit_fzf && bindkey '^p' fzf_ctrl_p

# lazy load functions defined in dotfiles/zsh/functions
my_funcs=$HOME/dotfiles/zsh/functions
fpath=($my_funcs $fpath)
for func in $(ls $my_funcs); do autoload $func; done;

eval "$(direnv hook zsh)"
