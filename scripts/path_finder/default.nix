{ pkgs ? import <nixpkgs> { }, lib ? pkgs.lib, ... }:

let
  # typer doesn't support click 8 which is what's packaged upstream
  # https://github.com/NixOS/nixpkgs/issues/129479
  # override it here 👍👍
  python39Packages = pkgs.python39Packages.override {
    overrides = self: super: {
      click = super.click.overrideAttrs (old: rec {
        version = "7.1.2";
        src = super.fetchPypi {
          inherit version;
          pname = old.pname;
          sha256 = "d2b5255c7c6349bc1bd1e59e08cd12acbbd63ce649f2588755783aa94dfb6b1a";
        };
      });
    };
  };

in

pkgs.python39Packages.buildPythonApplication {
  pname = "path_finder";
  src = ./.;
  # src = pkgs.lib.cleanSource ./.;
  version = "0.0.1";
  checkInputs = with python39Packages; [ pytest ];
  test = "pytest";
  propagatedBuildInputs = with python39Packages; [ typer ];
}
