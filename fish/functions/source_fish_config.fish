function source_fish_config
	set -l config_file ~/dotfiles/fish/config.fish
set -l first_arg $argv[1]

if test -f first_arg
set -l config_file $first_arg
end

source $config_file
end
