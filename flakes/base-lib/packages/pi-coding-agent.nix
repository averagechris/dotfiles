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
      hash = "sha256-v2HGScRzUVpfC2j7x32kDaHmTQBmJc6i2SbvPPEdPvE=";
    };
    x86_64-darwin = {
      platform = "darwin-x64";
      hash = "sha256-2jgziaWiYrmOx2rHcwdvJq1nBudQTBx8y2T1oUMBL/o=";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha256-58Zv6Mo2mfKs6UHCUxhdfvAAiXu1CobIs1DfPHuI7A0=";
    };
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha256-8Q0eJDqO42X+rIqO/TJXSJs74aZvAwNDnnFbBGNsUAQ=";
    };
  };

  asset =
    assets.${stdenv.hostPlatform.system}
      or (throw "pi-coding-agent: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "pi-coding-agent";
    version = "0.80.5";

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
