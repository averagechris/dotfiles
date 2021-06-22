{ pkgs, ... }:

let isLinux = pkgs.stdenv.hostPlatform.isLinux;
in {
  if isLinux: then {
    home.packages = with pkgs.python39Packages; [
      black
      epc
      flake8
      importmagic
      isort
      pyflakes
      pytest
      python-language-server
      ipdb
      ipython
      poetry
      pre-commit
      python
    ];
  }
}
