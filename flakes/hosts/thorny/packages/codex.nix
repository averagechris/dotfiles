{pkgs}: let
  version = "0.160.0";
in
  pkgs.stdenvNoCC.mkDerivation {
    pname = "codex-cli";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-package-x86_64-unknown-linux-musl.tar.gz";
      hash = "sha256-T8xHq1f1L/dTY5Uah2EUbNEMgoi9hv7UVIfbsgSha3E=";
    };

    nativeBuildInputs = [pkgs.gnutar pkgs.gzip];
    dontBuild = true;
    dontFixup = true;

    unpackPhase = ''
      mkdir source
      tar -xzf "$src" -C source
      cd source
    '';

    installPhase = ''
      mkdir -p "$out"
      cp -R . "$out/"
    '';

    meta = {
      description = "OpenAI Codex CLI for Thorny";
      homepage = "https://github.com/openai/codex";
      license = pkgs.lib.licenses.asl20;
      platforms = ["x86_64-linux"];
      mainProgram = "codex";
    };
  }
