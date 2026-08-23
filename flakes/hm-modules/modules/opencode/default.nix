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
      package = python3Minimal;
      name = "python3";
      description = "Python runtime";
    }
    {
      package = ripgrep;
      name = "rg";
      description = "fast text/code search";
    }
  ];
  cfg = config.dotfiles.opencode;
  optimizedNodeModules = pkgs.opencode.node_modules.overrideAttrs (old: let
    buildSetupMarker = "export BUN_INSTALL_CACHE_DIR=$(mktemp -d)";
    markerParts = lib.splitString buildSetupMarker old.buildPhase;
  in
    assert lib.assertMsg (builtins.length markerParts == 2) ''
      OpenCode node_modules buildPhase marker drifted; update the direct-to-output injection
    ''; {
      buildPhase =
        lib.replaceString buildSetupMarker ''
          ${buildSetupMarker}
          mkdir -p "$out"
          cp -R . "$out"
          cd "$out"
        ''
        old.buildPhase;
      installPhase = ''
        runHook preInstall

        find "$out" -depth -mindepth 1 \
          ! -path '*/node_modules' \
          ! -path '*/node_modules/*' \
          \( ! -type d -o -empty \) \
          -delete
        runHook postInstall
      '';
    });
  # Patches applied on top of the upstream opencode source (built from the
  # `github:anomalyco/opencode` flake input). Each patch targets a specific
  # upstream gap; when upstream incorporates the fix, the patch becomes a
  # no-op and should be removed. Detect stale/broken patches with:
  #   scripts/check-opencode-patches.sh
  # See docs/opencode-patches.md for the patch lifecycle.
  patchedOpencode = pkgs.opencode.overrideAttrs (old: {
    node_modules = optimizedNodeModules;
    patches =
      (old.patches or [])
      ++ [
        ./patches/opencode-allow-nix-bun-1-3-13.patch
        ./patches/opencode-strip-env-assignments.patch
        ./patches/opencode-fix-old-drizzle-migration-journal.patch
        ./patches/opencode-route-nested-prompts.patch
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
  # Concise Nix usage rule for agent prompts. Repeated `nix run` re-evaluates
  # and contends on the nix-db; see docs/suremac.md for background.
  nixUsageNote = "Nix: to run a flake app more than once, `nix build .#x` then `./result/bin/x`; do not repeat `nix run .#x` (each call re-evaluates). Treat `SQLite database is busy` as a harmless retry warning.";
  direnvNote = lib.optionalString cfg.direnv.enable " Shell commands automatically load the direnv-allowed dev shell environment for their workdir (any repo, not just the session root); run project tooling directly instead of wrapping it in `nix develop --command` or `direnv exec`.";
  runtimeNote = "Your runtime is a ${systemName} environment. By default, your environment includes these additional tools: ${agentToolNote}. The project local dev shell may provide additional tooling.${direnvNote} ${nixUsageNote}";
  direnvPlugin = pkgs.replaceVars ./plugins/dotfiles-direnv.js {
    direnv = lib.getExe config.programs.direnv.package;
  };
  # Print shell exports that override opencode models for the current shell
  # session via OPENCODE_CONFIG_CONTENT (merged last, so it beats the managed
  # config) without touching any persistent configuration. The `oconf` shell
  # function evals this output so `oconf && opencode` works. Models come live
  # from `opencode models` and agents are discovered from the deployed config;
  # see docs/opencode.md.
  ocTrial = pkgs.writeShellApplication {
    name = "oconf";
    # fzf deliberately comes from the user's PATH (guarded at runtime) rather
    # than runtimeInputs, so a PATH-prefixed fzf can be swapped in tests.
    runtimeInputs = [pkgs.jq];
    text = builtins.readFile ./oconf.sh;
  };
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

    direnv.enable = lib.mkOption {
      type = lib.types.bool;
      default = config.programs.direnv.enable;
      defaultText = lib.literalExpression "config.programs.direnv.enable";
      description = ''
        Install an OpenCode plugin that resolves the direnv environment for
        each bash tool invocation's working directory and merges it into the
        command environment. This gives agents (including subagents working in
        other repos) project dev-shell tooling without `nix develop --command`
        or `direnv exec` wrappers. Only direnv-allowed `.envrc` files load.
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
    # Base opencode configuration (applied only when programs.opencode.enable = true)
    (lib.mkIf config.programs.opencode.enable {
      programs.opencode = {
        package = lib.mkDefault opencodePackage;

        # Global skills are sourced from repo-managed SKILL.md files under
        # flakes/hm-modules/modules/opencode/skills/ and deployed to
        # ~/.config/opencode/skills/.

        # Global commands are sourced from repo-managed Markdown files under
        # flakes/hm-modules/modules/opencode/commands/.
        commands.what = ./commands/what.md;

        agents = import ./primary-agents.nix {
          inherit runtimeNote;
          agentSelectionPolicy = builtins.readFile ./agent-selection-policy.md;
          agentSelectionTable = builtins.readFile ./agent-selection-table.md;
        };

        # ============================================================================
        # SKILLS - Reusable knowledge for agents
        # ============================================================================

        skills = import ./skills.nix;

        # ============================================================================
        # SETTINGS - OpenCode configuration (written to config.json)
        # ============================================================================

        settings = import ./settings.nix {inherit lib pkgs managedJjWorkspaceExternalDirectories;};
      };

      # Registered through the shared skill registry (rather than skills.nix)
      # so other modules can extend it: dev-cache appends host-specific
      # sccache guidance via extraText when enabled.
      dotfiles.agentSkills.rust-cargo.source = lib.mkDefault ./skills/rust-cargo/SKILL.md;
      dotfiles.agentSkills.databricks-cli.source = lib.mkDefault ./skills/databricks-cli;

      home.packages =
        (map (tool: tool.package) installedAgentTools)
        ++ cfg.agentSupportPackages
        ++ [ocTrial];

      # The oconf helper prints export lines; eval them in the current shell
      # so `oconf && opencode` launches with the overrides applied.
      programs.zsh.initContent = ''
        # Apply oconf model-trial exports in the current shell.
        oconf() {
          local exports
          exports=$(command oconf "$@") || return $?
          eval "''${exports}"
        }
      '';

      programs.bash.initExtra = ''
        # Apply oconf model-trial exports in the current shell.
        oconf() {
          local exports
          exports=$(command oconf "$@") || return $?
          eval "''${exports}"
        }
      '';

      # These helpers were copied as writable files rather than managed symlinks,
      # so remove leftovers from profiles that previously enabled them.
      home.activation.remove-retired-opencode-review-tools = lib.hm.dag.entryAfter ["writeBoundary"] ''
        tools_dir="${config.home.homeDirectory}/.config/opencode/tools"
        if [[ -d "$tools_dir" ]]; then
          ${pkgs.coreutils}/bin/rm -f \
            "$tools_dir/review-artifact-generate.ts" \
            "$tools_dir/review-artifact-render-demo.ts" \
            "$tools_dir/review-artifact-render.ts" \
            "$tools_dir/review-artifact-write.ts" \
            "$tools_dir/review-github-post.ts"
          ${pkgs.coreutils}/bin/rmdir --ignore-fail-on-non-empty "$tools_dir"
        fi
      '';
    })

    # Per-workdir direnv environments for agent shell commands
    (lib.mkIf (config.programs.opencode.enable && cfg.direnv.enable) {
      xdg.configFile."opencode/plugins/dotfiles-direnv.js".source = direnvPlugin;
    })

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
