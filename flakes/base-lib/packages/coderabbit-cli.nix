{
  fetchurl,
  lib,
  stdenv,
  unzip,
}: let
  assets = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-TG+WrDbWS+r6g9r+zmUXnhkTyEMu8Bjr6D/GwItoEjE=";
    };
    x86_64-darwin = {
      platform = "darwin-x64";
      hash = "sha256-t6qNYq5LzOhlITigZYtyDvURaS4EqiyrI4td8qKZskc=";
    };
  };

  asset =
    assets.${stdenv.hostPlatform.system}
      or (throw "coderabbit-cli: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "coderabbit-cli";
    version = "0.6.4";

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
