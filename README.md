## How to get started on a new system
  * [install nix](https://nixos.org "nixos")
  * [install home-manager](https://github.com/nix-community/home-manager#installation)
  * install gnu stow `nix-env -Ia nixpkgs.stow`
  * clone dotfiles
  * change into the `dotfiles/stowed` directory
  * run `stow nixpkgs -t ~`
  * run `home-manager switch`


  * TODO: add spacemacs private layer into stowed
  * TODO: add tmux.conf to home-manager

### TODO: for macos
  * move skhd, yabai, karabiner to stowed
  * move start_scripts to home-manager
