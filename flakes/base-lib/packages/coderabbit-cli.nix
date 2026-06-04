{
  fetchurl,
  lib,
  stdenv,
  unzip,
}: let
  assets = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-b8Q38AuPATPChfycad2J2vpqEZLl3a3G1pTB91kWwHM=";
    };
    x86_64-darwin = {
      platform = "darwin-x64";
      hash = "sha256-pDv+NDETQrpqSVKYsmS5YDx68I6fidLMm+a4VZhf1Xk=";
    };
  };

  asset =
    assets.${stdenv.hostPlatform.system}
      or (throw "coderabbit-cli: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "coderabbit-cli";
    version = "0.5.3";

    src = fetchurl {
      url = "https://cli.coderabbit.ai/releases/${finalAttrs.version}/coderabbit-${asset.platform}.zip";
      inherit (asset) hash;
    };

    nativeBuildInputs = [unzip];

    dontBuild = true;

    unpackPhase = ''
      runHook preUnpack
      unzip -q "$src"
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      install -Dm755 coderabbit "$out/bin/coderabbit"
      ln -s "$out/bin/coderabbit" "$out/bin/cr"

      runHook postInstall
    '';

    meta = {
      description = "AI code review CLI from CodeRabbit";
      homepage = "https://docs.coderabbit.ai/cli";
      license = lib.licenses.unfree;
      mainProgram = "coderabbit";
      platforms = builtins.attrNames assets;
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
    };
  })
