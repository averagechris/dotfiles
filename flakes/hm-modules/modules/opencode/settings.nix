{
  lib,
  pkgs,
}: {
  # MCP Servers - External tool integrations
  mcp = {
    # Context7 - Search documentation for various tools and frameworks
    context7 = {
      type = "remote";
      url = "https://mcp.context7.com/mcp";
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

    github = {
      type = "remote";
      url = "https://api.githubcopilot.com/mcp/";
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
