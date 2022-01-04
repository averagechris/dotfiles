{ pkgs, sli-repo }:

with pkgs.poetry2nix;

let
  sli = mkPoetryApplication {
    projectDir = sli-repo;
    src = sli-repo;
    overrides = [
      defaultPoetryOverrides
      (self: super: {

        humanize = super.humanize.overridePythonAttrs (old: {
          postPatch = old.postPatch or "" + ''
            sed -i '/\[metadata\]/aversion = ${old.version}' setup.cfg
          '';
        });

        requests-mock = super.requests-mock.overridePythonAttrs (old: {
          buildInputs = old.buildInputs ++ [ self.pbr ];
        });

        inquirer = super.inquirer.overridePythonAttrs (
          old: {
            preBuild = old.preBuild or "" + ''
              substituteInPlace setup.py --replace 'version = "3.0.0"' 'version = "2.8.0"'
            '';
            preConfigure = (old.preConfigure or "") + ''cat << EOF > requirements.txt
blessed==1.19.0
readchar==2.0.1
python-editor==1.0.4
EOF
              '';
          }
        );


      })
    ];
  };

in
sli
