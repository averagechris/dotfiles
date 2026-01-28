{pkgs, ...}: {
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
