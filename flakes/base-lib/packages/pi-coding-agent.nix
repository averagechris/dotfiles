{
  autoPatchelfHook,
  fetchurl,
  lib,
  stdenv,
  zlib,
}: let
  assets = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-FH/DxFHsVDoVECryUc4xYHnI/K3+iuTT/+4gI0bpvtk=";
    };
    x86_64-darwin = {
      platform = "darwin-x64";
      hash = "sha256-mrEuQG5UW+Ex0SeamiwNXA1KPG6dhqUnAKehNaRFBBs=";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha256-uE+QFmEMc43ZRA32L2SYgNvplR25enrpNsvykoUOmAI=";
    };
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha256-sGJetiMZewr+IMhw0h7y80SB8VBOV3ffP2mKZsdjb18=";
    };
  };

  asset =
    assets.${stdenv.hostPlatform.system}
      or (throw "pi-coding-agent: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "pi-coding-agent";
    version = "0.83.0";

    src = fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${finalAttrs.version}/pi-${asset.platform}.tar.gz";
      inherit (asset) hash;
    };

    sourceRoot = "pi";

    nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      autoPatchelfHook
    ];

    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      stdenv.cc.cc.lib
      zlib
    ];

    dontBuild = true;

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin $out/libexec/pi
      cp -R . $out/libexec/pi/
      ln -s $out/libexec/pi/pi $out/bin/pi

      runHook postInstall
    '';

    meta = {
      description = "Minimal terminal coding harness";
      homepage = "https://pi.dev/";
      changelog = "https://github.com/earendil-works/pi/releases/tag/v${finalAttrs.version}";
      license = lib.licenses.mit;
      mainProgram = "pi";
      platforms = builtins.attrNames assets;
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
    };
  })
