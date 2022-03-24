{ pkgs ? import <nixpkgs> { }, lib ? pkgs.lib, ... }:
pkgs.python39Packages.buildPythonApplication {
  pname = "path_finder";
  src = pkgs.lib.cleanSource ./.;
  version = "0.0.1";
  checkInputs = with pkgs.python39Packages; [ pytestCheckHook ];
  propagatedBuildInputs = with pkgs.python39Packages; [ typer ];
}
