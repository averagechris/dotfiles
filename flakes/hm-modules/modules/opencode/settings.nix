{
  lib,
  managedJjWorkspaceExternalDirectories,
  pkgs,
}: let
  npxMcp = pkgs.writeShellApplication {
    name = "opencode-npx-mcp";
    runtimeInputs = [pkgs.nodejs];
    text = ''
      exec npx "$@"
    '';
  };
in {
  # Make cost-aware decomposition and Minion-first routing the normal entry
  # point instead of falling back to OpenCode's built-in Build agent.
  default_agent = "orchestrator";

  # Upstream defaults to 1, which lets only primary sessions delegate. Permit
  # one deliberate nested handoff while keeping deeper delegation bounded.
  subagent_depth = 2;

  # Keep the built-in exploration prompt and tools, but use a fast model with
  # enough reasoning for cross-file codebase research.
  agent.explore = {
    model = "openrouter/openai/gpt-5.6-luna";
    variant = "medium";
  };

  # Managed jj workspaces and temporary files live outside the OpenCode
  # process's project root. Trust the canonical workspace namespaces and common
  # temp paths, including both macOS's visible and canonical path spellings.
  # The Nix store is immutable to normal users and is useful build context, so
  # allow agents to inspect package sources and outputs there without prompting.
  permission.external_directory =
    {
      "*" = "ask";
      "/nix/store/**" = "allow";
      "/tmp/**" = "allow";
      "/private/tmp/**" = "allow";
      "/var/folders/**/T/opencode/**" = "allow";
      "/private/var/folders/**/T/opencode/**" = "allow";
    }
    // managedJjWorkspaceExternalDirectories;

  # MCP Servers - External tool integrations
  mcp = {
    # Context7 - Search documentation for various tools and frameworks
    context7 = {
      type = "remote";
      url = "https://mcp.context7.com/mcp";
      enabled = false;
    };

    # CircleCI - Pipeline, workflow, and build insights
    # Requires CIRCLECI_TOKEN in the environment when enabled.
    circleci = {
      type = "local";
      command = [
        (lib.getExe npxMcp)
        "-y"
        "@circleci/mcp-server-circleci@latest"
      ];
      enabled = false;
    };

    chrome-dev-tools = {
      type = "local";
      command = [
        (lib.getExe npxMcp)
        "-y"
        "chrome-devtools-mcp@latest"
        "--autoConnect"
      ];
      enabled = false;
    };

    datadog = {
      type = "remote";
      url = "https://mcp.datadoghq.com/api/unstable/mcp-server/mcp?toolsets=all";
      enabled = false;
    };

    # Grep by Vercel - Search code examples on GitHub
    gh-grep = {
      type = "remote";
      url = "https://mcp.grep.app";
      enabled = false;
    };

    # Gander - live jj code review session (routes to the workspace's
    # running gander TUI by cwd; snapshot fallback without one). Fails
    # harmlessly at startup outside jj repos.
    gander = {
      type = "local";
      command = ["gander" "mcp"];
      enabled = false;
    };

    github = {
      type = "remote";
      url = "https://api.githubcopilot.com/mcp/";
      enabled = false;
    };

    # Playwright - Browser automation MCP server
    playwright = {
      type = "local";
      command = [
        (lib.getExe npxMcp)
        "-y"
        "@playwright/mcp@latest"
      ];
      enabled = false;
    };

    # Notion - Hosted remote MCP with OAuth support
    notion = {
      type = "remote";
      url = "https://mcp.notion.com/mcp";
      oauth = {};
      enabled = false;
    };

    # Serena - Semantic code retrieval/editing tools for large codebases
    # Upstream currently recommends launching via uvx from the Git repository.
    serena = {
      type = "local";
      command = [
        (lib.getExe' pkgs.uv "uvx")
        "--from"
        "git+https://github.com/oraios/serena"
        "serena"
        "start-mcp-server"
      ];
      enabled = false;
    };

    # Sentry - Hosted remote MCP with OAuth support
    sentry = {
      type = "remote";
      url = "https://mcp.sentry.dev/mcp";
      oauth = {};
      enabled = false;
    };
  };
}
