{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    mdl
    nixpkgs-fmt
    pre-commit
    shellcheck
    shfmt
  ];
}
