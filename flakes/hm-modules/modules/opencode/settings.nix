{
  # MCP Servers - External tool integrations
  mcp = {
    # Context7 - Search documentation for various tools and frameworks
    context7 = {
      type = "remote";
      url = "https://mcp.context7.com/mcp";
      enabled = true;
    };

    # Grep by Vercel - Search code examples on GitHub
    gh-grep = {
      type = "remote";
      url = "https://mcp.grep.app";
      enabled = true;
    };
  };
}
