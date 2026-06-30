{
  fetchurl,
  lib,
  makeWrapper,
  nodejs_22,
  stdenvNoCC,
}: let
  nodejs = nodejs_22;
in
  stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "sentry";
    version = "0.38.0";

    src = fetchurl {
      url = "https://registry.npmjs.org/sentry/-/sentry-${finalAttrs.version}.tgz";
      hash = "sha256-2Z+fZdu0PwjB2mju8av7dsAtPrA4zVX75BprYFoNKao=";
    };

    nativeBuildInputs = [makeWrapper];

    sourceRoot = "package";

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/libexec/sentry" "$out/bin" "$out/share/doc/sentry"
      cp -R dist package.json "$out/libexec/sentry/"
      cp LICENSE.md README.md "$out/share/doc/sentry/"

      makeWrapper ${lib.getExe nodejs} "$out/bin/sentry" \
        --add-flags "$out/libexec/sentry/dist/bin.cjs" \
        --set-default SENTRY_CLI_NO_UPDATE_CHECK 1

      runHook postInstall
    '';

    installCheckPhase = ''
      runHook preInstallCheck
      export HOME="$TMPDIR/sentry-home"
      mkdir -p "$HOME"
      "$out/bin/sentry" --version
      runHook postInstallCheck
    '';
    doInstallCheck = true;

    meta = {
      description = "Sentry command-line interface for humans and agents";
      homepage = "https://cli.sentry.dev/";
      changelog = "https://github.com/getsentry/cli/releases/tag/v${finalAttrs.version}";
      license = lib.licenses.fsl11Asl20;
      mainProgram = "sentry";
      platforms = nodejs.meta.platforms;
    };
  })
