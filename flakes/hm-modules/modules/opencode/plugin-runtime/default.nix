{buildNpmPackage}:
buildNpmPackage {
  pname = "dotfiles-opencode-plugin-runtime";
  version = "2.0.3";
  src = ./.;
  npmDepsHash = "sha256-kbSSzb2eJkFLN163JFSAy3soSzng0BTYKaImYVpRvH4=";
  dontNpmBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -R node_modules "$out/"
    runHook postInstall
  '';
}
