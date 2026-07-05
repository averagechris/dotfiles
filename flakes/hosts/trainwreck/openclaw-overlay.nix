# Local overlay for openclaw-gateway on trainwreck.
#
# Upstream nix-openclaw's fetchPnpmDeps uses `pnpm install --force`, which
# downloads every platform variant of large optional native packages (Claude
# agent SDK, OpenAI Codex, GitHub Copilot, node-llama-cpp, etc.). Trainwreck
# only needs the aarch64-linux variants, so drop --force and let pnpm fetch
# only the optional deps matching npm_config_arch / npm_config_platform.
final: prev: {
  openclaw-gateway = prev.openclaw-gateway.overrideAttrs (old: {
    pnpmDeps = old.pnpmDeps.overrideAttrs (oldPnpm: {
      # Remove --force so pnpm skips optional deps for other platforms.
      installPhase = prev.lib.replaceStrings ["    --force \\\n"] [""] oldPnpm.installPhase;
      # The store content is now platform-specific, so the upstream hash no
      # longer applies. Compute this once with lib.fakeHash and fill it in.
      outputHash = "sha256-vVWT1VOmLHoxwsB3x5EwmxxwkE0T2FsFBgDNdqTpaNM=";
    });
  });

  openclaw = prev.openclaw.override {
    inherit (final) openclaw-gateway;
  };
}
