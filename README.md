# How to get started on a new system

A lot of this is kinda out of date since I switched to flakes.
So take with a grain of salt

- [install nix](https://nixos.org/download.html#nix-quick-install "nixos")

  - NOTE: double check all the install commands if something goes wrong,
    things may have changed upstream

  ```shell
  sh <(curl -L https://nixos.org/nix/install) --daemon
  ```

  - on recent versions of macos you'll need to add a special flag

  ```shell
  sh <(curl -L https://nixos.org/nix/install) \
      --darwin-use-unencrypted-nix-store-volume \
      --daemon
  ```

- [install nix-darwin](https://github.com/LnL7/nix-darwin#install "nix-darwin-install-instructions")
  if on macos

  ```shell
  nix-build https://github.com/LnL7/nix-darwin/archive/master.tar.gz -A installer
  ./result/bin/darwin-installer
  ```

- [install home-manager](https://github.com/nix-community/home-manager#installation)
  follow the instructions at the link

  - if on macos also follow the instructions for integrating home-manager as a nix-darwin
    module [instructions](https://nix-community.github.io/home-manager/index.html#sec-install-nix-darwin-module)

- clone this repo

  ```shell
  git clone https://github.com/averagechris/dotfiles.git
  ```

- create `localhome/default.nix` based on `localhome/example.nix`

  ```shell
  cp ~/dotfiles/nixpkgs/localhome/example.nix ~/dotfiles/nixpkgs/localhome/default.nix
  ```

  - modify `localhome/default.nix` according to the needs of the system
    (like choosing what to install and some PII info)

- create `darwin/pii.nix` based on `darwin/example_pii.nix`

  ```shell
  cp ~/dotfiles/nixpkgs/darwin/pii.nix ~/dotfiles/nixpkgs/darwin/pii.nix
  ```

  - modify `darwin/pii.nix` by adding the right user name and home directory

- create a symbolic link of `~/dotfiles/nixpkgs` to `~/.config/`

  ```shell
  ln -fs ~/dotfiles/nixpkgs ~/.config/
  ```

- build the configuration

  - for non-macos

    ```shell
    home-manager switch
    ```

  - if on macos
    (only the first call to darwin-rebuild requires the darwin-config argument)

    ```shell
    darwin-rebuild switch -I "darwin-config=$HOME/.config/nixpkgs/darwin/configuration.nix"
    ```

- finish installing emacs dependencies by starting emacs and running the following
  functions

  - `all-the-icons-install-fonts` to install the fonts used for icons
  - `emojify-download-emoji` to be able to display emoji characters
  - on macos: optionally allow emacs to "control your computer" in
    **Settings > Accessibility** to allow `emacs-everywhere` to work.

## Things to remember

- to update to the latest packages run `nix-channel --update`
  before running `home-manager switch` or `darwin-rebuild`

## TODO: for macos

- move start_scripts to home-manager
- `pkgs.emacsMacport` does not have a gui launcher add one upstream or make a wrapper,
  right now you have to use `open -a ~/.nix-profile/Applications/Emacs.app` and
  start the server from within emacs, you can't do `emacs --daemon` that doesn't
  work (should fix that as well at some point)

## Notes

### zsh

- if zsh start up is really slow, first try restarting computer, then try running
  zsh with `zsh -lvx`.

## Troubleshooting

### Start Over get rid of nix completely

- `rm -rf /nix`
  - if you get an error on macos remove nix from `/synthetic.conf` and try again
- on macos use disk utility app to delete the `nix` apfs volume
- restart system
- nix is now gone completely so you can follow the install instructions to start
  over

### After macos update / upgrade

- tl;dr; these can sometimes replace the changes necessary in
  `/etc/zprofile` and `/etc/zshrc` meaning we need to intervene manually.

```shell
sudo mv /etc/zshrc /etc/zshrc.bak
sudo mv /etc/zprofile /etc/zprofile.bak
sudo /nix/var/nix/profiles/system/activate
exit  # Start a new shell to reload the environment.
```
