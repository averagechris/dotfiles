{ pkgs, ... }:

{
  home.packages = with pkgs.python39Packages; [ black ipdb ipython python ];
}
