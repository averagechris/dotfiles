{ pkgs, ... }:

{
  home.packages = with pkgs.python39Packages; [
    # black
    # epc
    # flake8
    # importmagic
    # isort
    # pyflakes
    # pytest
    # python-language-server
    ipdb
    ipython
    python
  ];
}
