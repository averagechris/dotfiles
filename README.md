## How to get started on a new system
  * [install nix](https://nixos.org "nixos")
  * [install home-manager](https://github.com/nix-community/home-manager#installation)
  * install gnu stow `nix-env -Ia nixpkgs.stow`
  * clone this repo
  * change into the `dotfiles/stowed` directory
  * create `localhome/default.nix` based on `localhome/example.nix`
    * this is for local machine specific config like user name, directory and anything else
  * if configuring email, edit `email/default.nix` to import the emails you want on this machine
    * use `email/example-email.nix` as a guide
  * run `stow nixpkgs -t ~`
  * run `home-manager switch`
  * start emacs and run
    * `all-the-icons-install-fonts` to install the fonts used for icons
    * `emojify-download-emoji` to be able to display emoji characters


### Things to remember
* to update to the latest packages run `nix-channel --update` before running `home-manager switch`
* Optionally run `stow $DIR -t ~` for any other $DIR in `~/dotfiles/stowed` to symlink the related configs


### TODO: for macos
  * move start_scripts to home-manager
  * emacsMacport does not have a gui launcher add one upstream or make a wrapper, right now you have to use `open -a ~/.nix-profile/Applications/Emacs.app` and start the server from within emacs, you can't do `emacs --daemon` that doesn't work (should fix that as well at somepoint)
