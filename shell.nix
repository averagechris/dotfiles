{ pkgs ? import <nixpkgs> { } }:

let
  pypkgs = with pkgs.python39Packages; [
    pkgs.python39
    pkgs.nodePackages.pyright

    pytest
    black
    isort
    flake8
    importmagic
  ];
in
pkgs.mkShell {
  buildInputs = with pkgs; [
    mdl
    nixpkgs-fmt
    pre-commit
    poetry
    shellcheck
    shfmt
  ] ++ pypkgs;

  shellHook = ''
    export PYTHONBREAKPOINT=ipdb.set_trace
    export PYTHONDONTWRITEBYTECODE=true
  '';
}
