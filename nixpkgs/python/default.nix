{ pkgs, ... }:

let
  utils = (import ../utils pkgs);
  pythonPackagesForLinux =
    if pkgs.stdenv.hostPlatform.isLinux then with pkgs.python39Packages; [
      ipython
      python
    ] else [ ];

  flake8GlobalConfig = {
    flake8 = {
      max-line-length = 120;
    };
  };

in
{
  home.packages = pythonPackagesForLinux;

  xdg.configFile.flake8.text = ''
    # Generated by home-manager from nixpkgs.python in ~/dotfiles
    # For a list of options see: https://flake8.pycqa.org/en/latest/manpage.html

    ${utils.mkINI flake8GlobalConfig}
  '';
}
