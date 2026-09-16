{
  lib,
  managedJjWorkspaceExternalDirectories,
  pkgs,
}: let
  compactionInputLimit = 370000;
  compactionBuffer = 20000;
  compactionOutputReserve = 128000;
  # V2 compacts at min(input - buffer, context - max(output, buffer)). The
  # catalog context limits for these models exceed the second term, so the
  # deliberately lowered input ceiling makes the first term exactly 350k.
  compactionThreshold =
    lib.min
    (compactionInputLimit - compactionBuffer)
    (1000000 - lib.max compactionOutputReserve compactionBuffer);
  locallyCompactedModels = [
    "~openai/gpt-sol-latest"
    "~openai/gpt-astra-latest"
    "openai/gpt-5.6-sol"
    "openai/gpt-5.6-luna"
    "anthropic/claude-fable-5.1"
  ];
  npxMcp = pkgs.writeShellApplication {
    name = "opencode-npx-mcp";
    runtimeInputs = [pkgs.nodejs];
    text = ''
      exec npx "$@"
    '';
  };
in
  assert lib.assertMsg (compactionThreshold == 350000) "OpenCode compaction threshold must remain 350k tokens";
  assert lib.assertMsg (230000 < compactionThreshold) "230k-token OpenCode sessions must remain below automatic compaction"; {
    # Make cost-aware decomposition and Minion-first routing the normal entry
    # point instead of falling back to OpenCode's built-in Build agent.
    default_agent = "orchestrator";

    # Upstream defaults to 1, which lets only primary sessions delegate. Permit
    # one deliberate nested handoff while keeping deeper delegation bounded.
    experimental.subagent_depth = 2;

    # Use V2's local summary compaction. OpenRouter does not support native
    # provider compaction, and setting only limit.input preserves every catalog
    # model's truthful context/output limits, ID, and capabilities.
    compaction = {
      auto = true;
      keep.tokens = 15000;
      buffer = compactionBuffer;
    };
    warming = false;
    providers.openrouter.models = lib.genAttrs locallyCompactedModels (_: {
      limit.input = compactionInputLimit;
      compaction.mode = "local";
    });

    # Keep the built-in exploration prompt and tools, but use a fast model with
    # enough reasoning for cross-file codebase research.
    agents.explore = {
      model = "openrouter/openai/gpt-5.6-luna#medium";
    };

    # Managed jj workspaces and temporary files live outside the OpenCode
    # process's project root. Trust the canonical workspace namespaces and common
    # temp paths, including both macOS's visible and canonical path spellings.
    # The Nix store is immutable to normal users and is useful build context, so
    # allow agents to inspect package sources and outputs there without prompting.
    permissions =
      lib.mapAttrsToList (resource: effect: {
        action = "external_directory";
        inherit resource effect;
      }) ({
          "*" = "ask";
          "/nix/store/**" = "allow";
          "/tmp/**" = "allow";
          "/private/tmp/**" = "allow";
          "/var/folders/**/T/opencode/**" = "allow";
          "/private/var/folders/**/T/opencode/**" = "allow";
        }
        // managedJjWorkspaceExternalDirectories);

    # MCP Servers - External tool integrations
    mcp.servers = {
      # Context7 - Search documentation for various tools and frameworks
      context7 = {
        type = "remote";
        url = "https://mcp.context7.com/mcp";
        disabled = true;
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
        disabled = true;
      };

      chrome-dev-tools = {
        type = "local";
        command = [
          (lib.getExe npxMcp)
          "-y"
          "chrome-devtools-mcp@latest"
          "--autoConnect"
        ];
        disabled = true;
      };

      datadog = {
        type = "remote";
        url = "https://mcp.datadoghq.com/api/unstable/mcp-server/mcp?toolsets=all";
        disabled = true;
      };

      # Grep by Vercel - Search code examples on GitHub
      gh-grep = {
        type = "remote";
        url = "https://mcp.grep.app";
        disabled = true;
      };

      # Gander - live jj code review session (routes to the workspace's
      # running gander TUI by cwd; snapshot fallback without one). Fails
      # harmlessly at startup outside jj repos.
      gander = {
        type = "local";
        command = ["gander" "mcp"];
        disabled = true;
      };

      github = {
        type = "remote";
        url = "https://api.githubcopilot.com/mcp/";
        disabled = true;
      };

      # Playwright - Browser automation MCP server
      playwright = {
        type = "local";
        command = [
          (lib.getExe npxMcp)
          "-y"
          "@playwright/mcp@latest"
        ];
        disabled = true;
      };

      # Notion - Hosted remote MCP with OAuth support
      notion = {
        type = "remote";
        url = "https://mcp.notion.com/mcp";
        oauth = {};
        disabled = true;
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
        disabled = true;
      };

      # Sentry - Hosted remote MCP with OAuth support
      sentry = {
        type = "remote";
        url = "https://mcp.sentry.dev/mcp";
        oauth = {};
        disabled = true;
      };
    };
  }
