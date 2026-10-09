{buildNpmPackage}:
buildNpmPackage {
  pname = "dotfiles-opencode-plugin-runtime";
  version = "2.0.26";
  src = ./.;
  npmDepsHash = "sha256-BB9xAyYiOnpNrymHjWM4BcJ51xR/3NLufZtP6y76xKQ=";
  dontNpmBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -R node_modules "$out/"
    runHook postInstall
  '';
}
