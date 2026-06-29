{
  fetchurl,
  lib,
  stdenv,
}: let
  version = "1.6.0";

  assets = {
    aarch64-darwin = {
      platform = "Darwin_arm64";
      hash = "sha256-NKd1ZWY3q6o9gQjtWHLve1uD+f9KQLAJQ6xAvw0NbMA=";
    };
    x86_64-darwin = {
      platform = "Darwin_x86_64";
      hash = "sha256-ES1FOLUwF4BpPMb62wwyJ8xfkfYd5HnVA2WR3L1/AOU=";
    };
    aarch64-linux = {
      platform = "Linux_arm64";
      hash = "sha256-JF1Ipq5k8+HWSk24uGrGry7ISVLpEz7QAPGMEBKEq0M=";
    };
    x86_64-linux = {
      platform = "Linux_x86_64";
      hash = "sha256-E978hR6vR69bPsgpup+GA4B8/jXY4PM0ATOZwU0SYWo=";
    };
  };

  asset =
    assets.${stdenv.hostPlatform.system}
      or (throw "pup: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation {
    pname = "pup";
    inherit version;

    src = fetchurl {
      url = "https://github.com/DataDog/pup/releases/download/v${version}/pup_${version}_${asset.platform}.tar.gz";
      inherit (asset) hash;
    };

    sourceRoot = ".";

    dontBuild = true;

    installPhase = ''
      runHook preInstall

      install -Dm755 pup "$out/bin/pup"
      install -Dm644 LICENSE "$out/share/doc/pup/LICENSE"
      install -Dm644 LICENSE-3rdparty.csv "$out/share/doc/pup/LICENSE-3rdparty.csv"
      install -Dm644 README.md "$out/share/doc/pup/README.md"

      runHook postInstall
    '';

    meta = {
      description = "Agent-ready CLI for Datadog's observability platform";
      homepage = "https://github.com/DataDog/pup";
      license = lib.licenses.asl20;
      mainProgram = "pup";
      platforms = builtins.attrNames assets;
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
    };
  }
