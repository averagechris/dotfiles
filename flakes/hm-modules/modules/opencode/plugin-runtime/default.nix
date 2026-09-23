{buildNpmPackage}:
buildNpmPackage {
  pname = "dotfiles-opencode-plugin-runtime";
  version = "2.0.8";
  src = ./.;
  npmDepsHash = "sha256-78C5J37FGp718XLKTl22sgapkzBLR8U//b3q0udMWYY=";
  dontNpmBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -R node_modules "$out/"
    runHook postInstall
  '';
}
