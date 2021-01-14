{ config, pkgs, ... }:


let
  spacevim = pkgs.fetchgit {
    url = "https://github.com/SpaceVim/SpaceVim.git";
    rev = "d870c6a1bc91437e77fee9eae62f67ef4cef6371";
    sha256 = "1c884yq5ihxj9qgsjbkwkffa3f5lcmkbnghws6gkkfsv8y66s1s1";
  };
in {
  programs.neovim = {
    enable = true;
    vimAlias = true;
    extraConfig = ''
      execute 'source' '${spacevim}/config/main.vim'
    '';
  };
}