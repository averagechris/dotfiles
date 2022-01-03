{ pkgs ? import <nixpkgs> { } }:

let
  # typer doesn't support click 8 which is what's packaged upstream
  # https://github.com/NixOS/nixpkgs/issues/129479
  # override it here 👍👍
  python39Packages = pkgs.python39Packages.override {
    overrides = self: super: {
      click = super.click.overrideAttrs (old: rec {
        version = "7.1.2";
        src = super.fetchPypi {
          inherit (old) pname;
          inherit version;
          sha256 = "d2b5255c7c6349bc1bd1e59e08cd12acbbd63ce649f2588755783aa94dfb6b1a";
        };
      });
    };
  };

  pypkgs = with python39Packages; [
    pkgs.python39
    pkgs.nodePackages.pyright

    black
    flake8
    importmagic
    ipdb
    ipython
    isort
    pytest
    typer
  ];

in

pkgs.mkShell {
  buildInputs = with pkgs; [
    mdl
    nixpkgs-fmt
    pre-commit
    shellcheck
    shfmt
    statix
  ] ++ pypkgs;

  shellHook = ''
    export PYTHONBREAKPOINT=ipdb.set_trace;
    export PYTHONDONTWRITEBYTECODE=true;
  '';
}
