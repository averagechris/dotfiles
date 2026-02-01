{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.opencode;
in {
  options.dotfiles.opencode = {
    openrouterApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a file containing the OpenRouter API key.
        When set, the OPENROUTER_API_KEY environment variable will be
        exported in the shell, allowing opencode to authenticate without
        an interactive auth step.
      '';
      example = "/run/agenix/openrouter-api-key";
    };
  };

  config = lib.mkMerge [
    # Base opencode configuration (always applied when programs.opencode.enable = true)
    {
      programs.opencode = {
        # Global skills are now defined as SKILL.md files in ~/.config/opencode/skill/
        # See the skill directory for jj-vcs and nix-dotfiles skills

        agents = (import ./primary-agents.nix) // (import ./subagents.nix);

        # ============================================================================
        # CUSTOM COMMANDS - Run with /command-name
        # ============================================================================

        commands = import ./commands.nix;

        # ============================================================================
        # SKILLS - Reusable knowledge for agents
        # ============================================================================

        skills = import ./skills.nix;

        # ============================================================================
        # SETTINGS - OpenCode configuration (written to config.json)
        # ============================================================================

        settings = import ./settings.nix;
      };

      # Runtime dependencies for MCP servers
      home.packages = with pkgs; [
        playwright-mcp # Official Microsoft Playwright MCP server for browser automation
      ];
    }

    # OpenRouter API key configuration (only when openrouterApiKeyFile is set)
    (lib.mkIf (cfg.openrouterApiKeyFile != null) {
      # Export OPENROUTER_API_KEY in shell initialization
      # Using initContent to read the file at shell startup time
      programs.zsh.initContent = ''
        # OpenRouter API key for opencode (set by dotfiles.opencode.openrouterApiKeyFile)
        if [[ -r "${cfg.openrouterApiKeyFile}" ]]; then
          export OPENROUTER_API_KEY="$(cat "${cfg.openrouterApiKeyFile}")"
        fi
      '';

      programs.bash.initExtra = ''
        # OpenRouter API key for opencode (set by dotfiles.opencode.openrouterApiKeyFile)
        if [[ -r "${cfg.openrouterApiKeyFile}" ]]; then
          export OPENROUTER_API_KEY="$(cat "${cfg.openrouterApiKeyFile}")"
        fi
      '';
    })
  ];
}
