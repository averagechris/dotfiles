## How to get started on a new system
  * [install nix](https://nixos.org "nixos")
  * [install home-manager](https://github.com/nix-community/home-manager#installation)
  * install gnu stow `nix-env -Ia nixpkgs.stow`
  * clone dotfiles
  * change into the `dotfiles/stowed` directory
  * run `stow nixpkgs -t ~`
  * run `home-manager switch`

If on macos stow is also used for yabai, skhd and karabiner for now.



### TODO: for macos
  * move start_scripts to home-manager
  * emacsMacport does not have a gui launcher add one upstream or make a wrapper, right now you have to use `open -a ~/.nix-profile/Applications/Emacs.app` and start the server from within emacs, you can't do `emacs --daemon` that doesn't work (should fix that as well at somepoint)
