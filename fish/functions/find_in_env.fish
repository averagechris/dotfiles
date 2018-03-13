function find_in_env
    set fzf_helper_msg "Choose an environment variable"
    if echo $argv | grep -q .
      env | rg -i $argv | fzf -1 -0 --header "$fzf_helper_msg" | cut -d '=' -f 2
  else
      env | fzf -1 -0 --header "$fzf_helper_msg" | cut -d '=' -f 2
  end
end
