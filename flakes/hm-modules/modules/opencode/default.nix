{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  systemName =
    if pkgs.stdenv.hostPlatform.isDarwin
    then "macOS"
    else "NixOS";
  nodejsCommandPackage = pkgs.writeShellApplication {
    name = "nodejs";
    runtimeInputs = [pkgs.nodejs];
    text = ''
      exec node "$@"
    '';
  };
  defaultAgentTools = with pkgs; [
    {
      package = jujutsu;
      name = "jj";
      description = "Jujutsu VCS";
    }
    {
      package = nodejsCommandPackage;
      name = "nodejs";
      description = "JavaScript runtime";
    }
    {
      package = python313;
      name = "python3";
      description = "Python 3.13 runtime";
    }
    {
      package = ripgrep;
      name = "rg";
      description = "fast code search";
    }
  ];
  cfg = config.dotfiles.opencode;
  reviewToolsPath = ../../../../.opencode/tools;
  opencodePackage =
    if pkgs.stdenv.hostPlatform.isLinux
    then
      pkgs.symlinkJoin {
        inherit (pkgs.opencode) meta;
        name = "${lib.getName pkgs.opencode}-wrapped-${lib.getVersion pkgs.opencode}";
        paths = [pkgs.opencode];
        nativeBuildInputs = [pkgs.makeWrapper];
        postBuild = ''
          wrapProgram $out/bin/opencode \
            --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [pkgs.stdenv.cc.cc.lib]}
        '';
      }
    else pkgs.opencode;
  renderToolNote = tool:
    if tool.description == null
    then tool.name
    else "${tool.name} (${tool.description})";
  installedAgentTools = defaultAgentTools ++ cfg.agentTools;
  agentToolNote = lib.concatStringsSep ", " (map renderToolNote installedAgentTools);
  runtimeNote = "Your runtime is a ${systemName} environment. By default, your environment includes these additional tools: ${agentToolNote}. The project local dev shell may provide additional tooling.";
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

    circleciTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Path to a file containing the CircleCI API token.
        When set, the CIRCLECI_TOKEN environment variable will be exported in
        the shell, allowing CircleCI CLI and OpenCode CircleCI integrations to
        authenticate non-interactively.
      '';
      example = "/run/agenix/circleci-token";
    };

    agentTools = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule ({...}: {
        options = {
          package = lib.mkOption {
            type = lib.types.package;
            description = "Package to install for OpenCode agents.";
          };

          name = lib.mkOption {
            type = lib.types.str;
            description = "Short package or command name to mention in the agent prompt.";
          };

          description = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Extremely brief purpose note for the prompt when the tool name is not obvious.";
          };
        };
      }));
      default = [];
      defaultText = lib.literalExpression ''        with pkgs; [
                { package = jujutsu; name = "jj"; description = "Jujutsu VCS"; }
                { package = <nodejs-wrapper-package>; name = "nodejs"; description = "JavaScript runtime"; }
                { package = python313; name = "python3"; description = "Python 3.13 runtime"; }
                { package = ripgrep; name = "rg"; description = "fast code search"; }
              ]'';
      description = ''
        Host-specific OpenCode agent tools and their prompt metadata. These are
        appended to the module's built-in default tool list.
      '';
    };

    agentSupportPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      example = lib.literalExpression ''with pkgs; [ python313Packages.databricks-sql-connector ]'';
      description = ''
        Extra packages installed for OpenCode agents without mentioning them in
        the generated runtime note. Use this for implicit runtime dependencies
        that support a visible tool.
      '';
    };
  };

  config = lib.mkMerge [
    # Base opencode configuration (always applied when programs.opencode.enable = true)
    {
      programs.opencode = {
        package = lib.mkDefault opencodePackage;

        # Global skills are sourced from repo-managed SKILL.md files under
        # flakes/hm-modules/modules/opencode/skills/ and deployed to
        # ~/.config/opencode/skills/.

        agents = import ./primary-agents.nix {inherit runtimeNote;};

        # ============================================================================
        # CUSTOM COMMANDS - Run with /command-name
        # ============================================================================

        commands = import ./commands.nix;

        # Repo-managed PR review helpers. Use the home-manager OpenCode tools
        # option so these are installed as first-class OpenCode custom tools.
        tools = reviewToolsPath;

        # ============================================================================
        # SKILLS - Reusable knowledge for agents
        # ============================================================================

        skills =
          (import ./skills.nix)
          // (inputs.linear-cli.lib.opencodeSkills or {});

        # ============================================================================
        # SETTINGS - OpenCode configuration (written to config.json)
        # ============================================================================

        settings = import ./settings.nix {inherit lib pkgs;};
      };

      home.packages = (map (tool: tool.package) installedAgentTools) ++ cfg.agentSupportPackages;
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

    # CircleCI token configuration (only when circleciTokenFile is set)
    (lib.mkIf (cfg.circleciTokenFile != null) {
      # Export CIRCLECI_TOKEN in shell initialization
      # Using initContent/initExtra to read the file at shell startup time
      programs.zsh.initContent = lib.mkAfter ''
        # CircleCI token for opencode (set by dotfiles.opencode.circleciTokenFile)
        if [[ -r "${cfg.circleciTokenFile}" ]]; then
          export CIRCLECI_TOKEN="$(cat "${cfg.circleciTokenFile}")"
        fi
      '';

      programs.bash.initExtra = lib.mkAfter ''
        # CircleCI token for opencode (set by dotfiles.opencode.circleciTokenFile)
        if [[ -r "${cfg.circleciTokenFile}" ]]; then
          export CIRCLECI_TOKEN="$(cat "${cfg.circleciTokenFile}")"
        fi
      '';
    })
  ];
}
