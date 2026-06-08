{
  fetchurl,
  installShellFiles,
  lib,
  stdenv,
}: let
  assets = {
    aarch64-darwin = {
      platform = "aarch64-apple-darwin";
      hash = "sha256-i0gTlN4D7fzEcwijRWdY87P0crAfpvTNt2Mpym5vwPo=";
    };
  };

  asset =
    assets.${stdenv.hostPlatform.system}
      or (throw "notion-cli: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "notion-cli";
    version = "0.16.0";

    src = fetchurl {
      url = "https://ntn.dev/releases/v${finalAttrs.version}/ntn-${asset.platform}.tar.gz";
      inherit (asset) hash;
    };

    sourceRoot = "ntn-${asset.platform}";

    dontBuild = true;

    nativeBuildInputs = [installShellFiles];

    installPhase = ''
      runHook preInstall

      install -Dm755 ntn "$out/bin/ntn"
      install -Dm644 LICENSE.md "$out/share/licenses/${finalAttrs.pname}/LICENSE.md"
      install -Dm644 README.md "$out/share/doc/${finalAttrs.pname}/README.md"

      "$out/bin/ntn" completions bash > ntn.bash
      "$out/bin/ntn" completions fish > ntn.fish
      "$out/bin/ntn" completions zsh > _ntn
      installShellCompletion --cmd ntn \
        --bash ntn.bash \
        --fish ntn.fish \
        --zsh _ntn

      runHook postInstall
    '';

    meta = {
      description = "Command-line interface for Notion and Notion Workers";
      homepage = "https://developers.notion.com/cli";
      changelog = "https://ntn.dev/releases/v${finalAttrs.version}/";
      license = lib.licenses.mit;
      mainProgram = "ntn";
      platforms = builtins.attrNames assets;
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
    };
  })
