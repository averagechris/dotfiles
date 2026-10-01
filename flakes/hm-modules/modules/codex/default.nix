{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.codex;
  tomlFormat = pkgs.formats.toml {};
  python = pkgs.python3.withPackages (p: [p.tomlkit]);
  configDir =
    if config.home.preferXdgDirectories
    then "${config.xdg.configHome}/codex"
    else "${config.home.homeDirectory}/.codex";
  managedSettings = pkgs.writeText "codex-managed-settings.json" (builtins.toJSON cfg.settings);
  mergeSettings = pkgs.writeShellApplication {
    name = "dotfiles-codex-merge-settings";
    runtimeInputs = [python];
    text = ''
      exec python3 ${./merge-settings.py} "$@"
    '';
  };
in {
  imports = [../agent-workflows.nix];

  options.dotfiles.codex = {
    enable = lib.mkEnableOption "shared agent guidance and portable skills for Codex";
    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "Optional Codex CLI package; null uses the separately installed desktop app.";
    };
    settings = lib.mkOption {
      inherit (tomlFormat) type;
      default = {};
      description = "Non-secret settings merged into writable config.toml while preserving app-owned keys. Removed declarations are cleaned up if unchanged locally.";
    };
    extraInstructions = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional host-specific Codex guidance; do not put secrets here.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.codex = {
      enable = true;
      package = lib.mkDefault cfg.package;
      # The desktop app writes plugin, browser, and UI settings here.
      settings = lib.mkDefault null;
      context = lib.concatStringsSep "\n" [
        (builtins.readFile ../agent-guidance.md)
        (builtins.readFile ./AGENTS.md)
        cfg.extraInstructions
      ];
    };
    assertions = [
      {
        assertion =
          (config.programs.codex.settings == null || config.programs.codex.settings == {})
          && config.programs.codex.plugins == []
          && config.programs.codex.marketplaces == {}
          && !config.programs.codex.enableMcpIntegration;
        message = "dotfiles.codex preserves writable desktop config: use dotfiles.codex.settings for settings/MCP entries and the app for plugin installation, rather than programs.codex config writers.";
      }
    ];
    home.activation.mergeCodexSettings = lib.hm.dag.entryAfter ["linkGeneration"] ''
      run ${mergeSettings}/bin/dotfiles-codex-merge-settings \
        ${lib.escapeShellArg configDir} ${managedSettings}
    '';
  };
}
