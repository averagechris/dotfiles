{ pkgs, ... }:

let
  pythonPackagesForLinux =
    if pkgs.stdenv.hostPlatform.isLinux then with pkgs.python39Packages; [
      black
      epc
      flake8
      importmagic
      isort
      pyflakes
      pytest
      # python-language-server
      ipdb
      ipython
      poetry
      pre-commit
      python
    ] else [ ];

in
{
  home.packages = pythonPackagesForLinux;
}
