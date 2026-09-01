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
      hash = "sha256-xo46xNBbTigqqrLmx28WHT6eaPGaIuOJE8v6rbbIAPA=";
    };
    x86_64-darwin = {
      platform = "darwin-x64";
      hash = "sha256-egQtZBMGVCE4cAGkmGGQoaAxhslaaV9N7gvcduYN6Pc=";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha256-E1WA9rlCFRZG5nuLhm2YfSjOPP9aSXAwd13dKWWflD0=";
    };
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha256-wvPD5qGFC9h2VMw8qIEQEycjl8PQQqTipkxD7htCOXI=";
    };
  };

  asset =
    assets.${stdenv.hostPlatform.system}
      or (throw "pi-coding-agent: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "pi-coding-agent";
    version = "0.84.4";

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
