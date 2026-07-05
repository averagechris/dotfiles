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
      package = python314;
      name = "python3";
      description = "Python 3.14 runtime";
    }
    {
      package = ripgrep;
      name = "rg";
      description = "fast text/code search";
    }
  ];
  cfg = config.dotfiles.opencode;
  reviewToolsPath = ../../../../.opencode/tools;
  installedReviewToolsPath = "${config.home.homeDirectory}/.config/opencode/tools";
  opencodeNpmVersion = builtins.head (lib.splitString "+" (lib.getVersion pkgs.opencode));
  opencodePackageJson = builtins.toJSON {
    dependencies = {
      "@opencode-ai/plugin" = opencodeNpmVersion;
    };
  };
  # Patches applied on top of the upstream opencode source (built from the
  # `github:anomalyco/opencode` flake input). Each patch targets a specific
  # upstream gap; when upstream incorporates the fix, the patch becomes a
  # no-op and should be removed. Detect stale/broken patches with:
  #   scripts/check-opencode-patches.sh
  # See docs/opencode-patches.md for the patch lifecycle.
  patchedOpencode = pkgs.opencode.overrideAttrs (old: {
    patches =
      (old.patches or [])
      ++ [
        ./patches/opencode-allow-nix-bun-1-3-13.patch
        ./patches/opencode-strip-env-assignments.patch
        ./patches/opencode-fix-old-drizzle-migration-journal.patch
      ];
  });
  opencodePackage =
    if pkgs.stdenv.hostPlatform.isLinux
    then
      pkgs.symlinkJoin {
        inherit (patchedOpencode) meta;
        name = "${lib.getName patchedOpencode}-wrapped-${lib.getVersion patchedOpencode}";
        paths = [patchedOpencode];
        nativeBuildInputs = [pkgs.makeWrapper];
        postBuild = ''
          wrapProgram $out/bin/opencode \
            --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [pkgs.stdenv.cc.cc.lib]}
        '';
      }
    else patchedOpencode;
  renderToolNote = tool:
    if tool.description == null
    then tool.name
    else "${tool.name} (${tool.description})";
  installedAgentTools = defaultAgentTools ++ cfg.agentTools;
  agentToolNote = lib.concatStringsSep ", " (map renderToolNote installedAgentTools);
  runtimeNote = "Your runtime is a ${systemName} environment. By default, your environment includes these additional tools: ${agentToolNote}. The project local dev shell may provide additional tooling.";
  managedJjWorkspaceExternalDirectories = lib.listToAttrs (map (group: {
      name = "${group.path}/${group.workspaceDir}/**";
      value = "allow";
    })
    config.dotfiles.jujutsu.workspaces.projectGroups);
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

        # Repo-managed PR review helpers. Point OpenCode at the mutable config
        # copy, not the Nix store source path, so TypeScript import resolution
        # starts under ~/.config/opencode and can find node_modules there.
        tools = installedReviewToolsPath;

        # ============================================================================
        # SKILLS - Reusable knowledge for agents
        # ============================================================================

        skills =
          (import ./skills.nix)
          // (inputs.linear-cli.lib.opencodeSkills or {});

        # ============================================================================
        # SETTINGS - OpenCode configuration (written to config.json)
        # ============================================================================

        settings = import ./settings.nix {inherit lib pkgs managedJjWorkspaceExternalDirectories;};
      };

      home.packages = (map (tool: tool.package) installedAgentTools) ++ cfg.agentSupportPackages;

      # Custom tools import @opencode-ai/plugin. OpenCode waits for dependencies
      # before importing tools, but the current Nix-packaged build only reifies
      # dependencies already declared in the config directory. Declare the plugin
      # here so ~/.config/opencode/node_modules is populated on Linux and Darwin.
      xdg.configFile."opencode/package.json".text = opencodePackageJson;

      # Project-local OpenCode tools are only visible when opencode is launched
      # from this dotfiles checkout. `programs.opencode.tools` registers the
      # tools with OpenCode, then this activation materializes them as real files
      # (not symlinks into /nix/store) so TypeScript tool imports resolve against
      # ~/.config/opencode/node_modules.
      home.activation.install-opencode-review-tools = lib.hm.dag.entryAfter ["writeBoundary"] ''
        target="${installedReviewToolsPath}"
        ${pkgs.coreutils}/bin/rm -rf "$target"
        ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$target")"
        ${pkgs.coreutils}/bin/cp -R "${reviewToolsPath}" "$target"
        ${pkgs.coreutils}/bin/chmod -R u+w "$target"
      '';
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
