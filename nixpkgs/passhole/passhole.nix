{ pkgs }:

with pkgs.python39Packages;

let
  pykeepass_cache = buildPythonPackage rec {
    pname = "pykeepass-cache";
    version = "2.0.3";
    src = fetchPypi {
      inherit pname version;
      sha256 = "sha256-fzb+qC8dACPr+V31DV50ElHzIePdXMX6TtepTY6fYeg=";
    };
    propagatedBuildInputs = [
      pykeepass
      python-daemon
      rpyc
    ];
  };

in
buildPythonApplication rec {
  pname = "passhole";
  version = "1.9.7";
  src = fetchPypi {
    inherit pname version;
    sha256 = "sha256-0qOxGv6YdcK4AjbE+IbBxYNBe/NE/z4k6PuVGCPdjFk=";
  };
  propagatedBuildInputs = [
    colorama
    future
    pykeepass_cache
    pynput
    pyotp
  ];
}
