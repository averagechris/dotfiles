# https://github.com/dmaasland/lastpass-authenticator-export
{pkgs, ...}:
with pkgs;
  python39Packages.buildPythonApplication rec {
    pname = "lastpass-authenticator-export";
    version = "unstable-2022-03-31";
    src = fetchFromGitHub {
      owner = "dmaasland";
      repo = "lastpass-authenticator-export";
      rev = "154422b60152f328435e71bed722be5788808486";
      sha256 = "sha256-CmNBrEFuwWCdFijU5VUzg/zzLQ2ALaIjAWKtAZnehes=";
    };
    setup = ''
      from setuptools import find_packages, setup

      setup(
          name="${pname}",
          version="${version}",
          py_modules=["lastpass_authenticator_export"],
          entry_points={"console_scripts": ["lastpass_authenticator_export = lastpass_authenticator_export:main"]},
          pacakges=find_packages(),
      )
    '';
    postUnpack = ''
      echo '${setup}' > $sourceRoot/setup.py
      mv $sourceRoot/lastpass-authenticator-export.py $sourceRoot/lastpass_authenticator_export.py
    '';

    propagatedBuildInputs = with python39Packages; [
      requests
      pycryptodome
      qrcode
      pyotp
    ];
  }
