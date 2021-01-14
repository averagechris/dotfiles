  * [install nix](https://nixos.org "nixos")
  * [install home-manager](https://github.com/nix-community/home-manager#installation)
  * install gnu stow `nix-env -Ia nixpkgs.stow`
  * clone dotfiles
  * change into the `dotfiles/stowed` directory
  * run `stow nixpkgs -t ~`
  * run `home-manager switch`
