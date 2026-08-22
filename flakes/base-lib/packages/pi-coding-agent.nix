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
      hash = "sha256-yZboiLf33ORLzyT2kXasZGxEE505Fr1JprKOWoxeOmU=";
    };
    x86_64-darwin = {
      platform = "darwin-x64";
      hash = "sha256-gIzwKpPNYB0+oF1H3BXEUHSxIKyB3syGRM0+QKNYJOY=";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha256-0VNy2p5LTF/vn9Fb7XbX9fFyDdOf583g7GLltlrWPvE=";
    };
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha256-kG++eH/SJcSsYk/n69Wx1Vpg4PXH71F5XSMVZPnuHBM=";
    };
  };

  asset =
    assets.${stdenv.hostPlatform.system}
      or (throw "pi-coding-agent: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "pi-coding-agent";
    version = "0.84.2";

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
