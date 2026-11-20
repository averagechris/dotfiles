{buildNpmPackage}:
buildNpmPackage {
  pname = "dotfiles-opencode-plugin-runtime";
  version = "2.0.26";
  src = ./.;
  npmDepsHash = "sha256-e9lzSe7mP4lrINm16gNGQY9jk789bSBeC7tXhEUb9LU=";
  dontNpmBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -R node_modules "$out/"
    runHook postInstall
  '';
}
