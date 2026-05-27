{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.pi;
  defaultEnabledModels = [
    "anthropic/*opus*"
    "anthropic/*sonnet*"
    "anthropic/*haiku*"
    "openai/gpt-*"
    "moonshotai/*kimi*"
    "google/gemini*"
  ];
  defaultSettings = {
    defaultProvider = "openrouter";
    defaultModel = "openai/gpt-5.5";
    defaultThinkingLevel = "low";
    quietStartup = true;
    collapseChangelog = true;
    enableInstallTelemetry = false;
    enabledModels = defaultEnabledModels;
  };
  resourceSettings =
    lib.optionalAttrs (cfg.packages != []) {inherit (cfg) packages;}
    // lib.optionalAttrs (cfg.extensions != []) {inherit (cfg) extensions;}
    // lib.optionalAttrs (cfg.skills != []) {inherit (cfg) skills;}
    // lib.optionalAttrs (cfg.prompts != []) {inherit (cfg) prompts;}
    // lib.optionalAttrs (cfg.themes != []) {inherit (cfg) themes;};
  settings = lib.recursiveUpdate (lib.recursiveUpdate defaultSettings cfg.settings) resourceSettings;
  exportEnv = name: value: ''
    export ${name}=${lib.escapeShellArg value}
  '';
  shellEnvironment = lib.concatStringsSep "\n" (lib.mapAttrsToList exportEnv cfg.environment);
  openrouterEnvironment = lib.optionalString (cfg.openrouterApiKeyFile != null && cfg.exportOpenrouterEnv) ''
    if [[ -r ${lib.escapeShellArg cfg.openrouterApiKeyFile} ]]; then
      export OPENROUTER_API_KEY="$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg cfg.openrouterApiKeyFile})"
    fi
  '';
  shellInit = lib.concatStringsSep "\n" (lib.filter (fragment: fragment != "") [
    shellEnvironment
    openrouterEnvironment
  ]);
  renderArgs = wrapper:
    lib.concatStringsSep " " (map lib.escapeShellArg (
      (lib.optionals (wrapper.provider != null) ["--provider" wrapper.provider])
      ++ (lib.optionals (wrapper.model != null) ["--model" wrapper.model])
      ++ (lib.optionals (wrapper.thinking != null) ["--thinking" wrapper.thinking])
      ++ (lib.optionals (wrapper.models != []) ["--models" (lib.concatStringsSep "," wrapper.models)])
      ++ (lib.optionals (wrapper.tools != []) ["--tools" (lib.concatStringsSep "," wrapper.tools)])
      ++ (lib.optionals wrapper.noTools ["--no-tools"])
      ++ (lib.optionals wrapper.noBuiltinTools ["--no-builtin-tools"])
      ++ (lib.optionals wrapper.noSession ["--no-session"])
      ++ (lib.optionals wrapper.print ["--print"])
      ++ (lib.optionals wrapper.offline ["--offline"])
      ++ (lib.optionals (wrapper.systemPrompt != null) ["--system-prompt" wrapper.systemPrompt])
      ++ (lib.concatMap (prompt: ["--append-system-prompt" prompt]) wrapper.appendSystemPrompts)
      ++ wrapper.extraArgs
    ));
  wrapperPackages = lib.mapAttrsToList (name: wrapper:
    pkgs.writeShellApplication {
      name = wrapper.executableName;
      runtimeInputs = [cfg.package];
      text = ''
        exec ${lib.getExe cfg.package} ${renderArgs wrapper} "$@"
      '';
    })
  cfg.wrappers;
in {
  options.programs.pi = {
    enable = lib.mkEnableOption "Pi coding agent";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.pi;
      defaultText = lib.literalExpression "pkgs.pi";
      description = "Pi package to install.";
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      example = lib.literalExpression ''
        {
          defaultProvider = "openrouter";
          defaultModel = "openai/gpt-5.5";
          defaultThinkingLevel = "low";
          enabledModels = [
            "anthropic/*sonnet*"
            "anthropic/*haiku*"
            "openai/gpt-*"
            "moonshotai/*kimi*"
            "google/gemini*"
          ];
        }
      '';
      description = ''
        Settings written to ~/.pi/agent/settings.json. These values are merged
        over the module defaults, which use OpenRouter, openai/gpt-5.5, low
        thinking, quiet startup, no install telemetry, and the default enabled
        model patterns.
      '';
    };

    models = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      example = lib.literalExpression ''
        {
          providers.openrouter.modelOverrides."openai/gpt-5.5" = {
            reasoning = true;
            input = ["text" "image"];
          };
        }
      '';
      description = ''
        Optional custom model/provider configuration written to
        ~/.pi/agent/models.json. Leave empty to avoid managing the file.
      '';
    };

    openrouterApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Path to a file containing the OpenRouter API key. When set with
        exportOpenrouterEnv, OPENROUTER_API_KEY is read from this file during
        shell initialization so Pi can authenticate without /login.
      '';
      example = "/run/agenix/openrouter-api-key";
    };

    exportOpenrouterEnv = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Export OPENROUTER_API_KEY from openrouterApiKeyFile in interactive shell
        initialization. This mirrors the OpenCode module and makes the key
        available to Pi subprocesses and extensions.
      '';
    };

    manageOpenrouterAuthFile = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        When openrouterApiKeyFile is set, write ~/.pi/agent/auth.json with an
        OpenRouter api_key entry that shells out to cat the key file. This keeps
        Pi's OpenRouter model catalog available even before shell initialization
        has exported OPENROUTER_API_KEY, avoiding enabledModels warnings.

        Disable this if you want Pi to manage auth.json itself with /login or
        additional provider credentials.
      '';
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        PI_SKIP_VERSION_CHECK = "1";
        PI_TELEMETRY = "0";
      };
      description = ''
        Extra environment variables exported in shell initialization for Pi.
        By default, Nix-managed Pi skips upstream version checks and install
        telemetry.
      '';
    };

    packages = lib.mkOption {
      type = lib.types.listOf (lib.types.oneOf [lib.types.str lib.types.attrs]);
      default = [];
      description = "Pi package sources to load from settings.json.";
    };

    extensions = lib.mkOption {
      type = lib.types.listOf (lib.types.oneOf [lib.types.str lib.types.path]);
      default = [];
      description = "Local Pi extension files or directories to load.";
    };

    skills = lib.mkOption {
      type = lib.types.listOf (lib.types.oneOf [lib.types.str lib.types.path]);
      default = [];
      description = "Local Pi skill files or directories to load.";
    };

    prompts = lib.mkOption {
      type = lib.types.listOf (lib.types.oneOf [lib.types.str lib.types.path]);
      default = [];
      description = "Local Pi prompt template files or directories to load.";
    };

    themes = lib.mkOption {
      type = lib.types.listOf (lib.types.oneOf [lib.types.str lib.types.path]);
      default = [];
      description = "Local Pi theme JSON files or directories to load.";
    };

    wrappers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
        options = {
          executableName = lib.mkOption {
            type = lib.types.str;
            default = "pi-${name}";
            description = "Name of the wrapper executable.";
          };

          provider = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Provider passed with --provider.";
          };

          model = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Model passed with --model.";
          };

          thinking = lib.mkOption {
            type = lib.types.nullOr (lib.types.enum ["off" "minimal" "low" "medium" "high" "xhigh"]);
            default = null;
            description = "Thinking level passed with --thinking.";
          };

          models = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Model cycle patterns passed with --models.";
          };

          tools = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Tool allowlist passed with --tools.";
          };

          noTools = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Pass --no-tools.";
          };

          noBuiltinTools = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Pass --no-builtin-tools.";
          };

          noSession = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Pass --no-session.";
          };

          print = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Pass --print for non-interactive mode.";
          };

          offline = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Pass --offline.";
          };

          systemPrompt = lib.mkOption {
            type = lib.types.nullOr lib.types.lines;
            default = null;
            description = "System prompt passed with --system-prompt.";
          };

          appendSystemPrompts = lib.mkOption {
            type = lib.types.listOf lib.types.lines;
            default = [];
            description = "Prompt fragments passed with repeated --append-system-prompt.";
          };

          extraArgs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Additional fixed arguments passed before user arguments.";
          };
        };
      }));
      default = {};
      example = lib.literalExpression ''
        {
          readonly.tools = ["read" "grep" "find" "ls"];
          deep = {
            model = "openrouter/anthropic/claude-opus-4.5";
            thinking = "high";
          };
        }
      '';
      description = "Named Pi wrapper commands installed as home packages.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [cfg.package] ++ wrapperPackages;

    home.file.".pi/agent/settings.json".text = builtins.toJSON settings;

    home.file.".pi/agent/auth.json" = lib.mkIf (cfg.openrouterApiKeyFile != null && cfg.manageOpenrouterAuthFile) {
      text = builtins.toJSON {
        openrouter = {
          type = "api_key";
          key = "!${pkgs.coreutils}/bin/cat ${lib.escapeShellArg cfg.openrouterApiKeyFile}";
        };
      };
    };

    home.file.".pi/agent/models.json" = lib.mkIf (cfg.models != {}) {
      text = builtins.toJSON cfg.models;
    };

    programs.zsh.initContent = lib.mkIf (shellInit != "") (lib.mkAfter ''
      # Pi coding agent environment (set by programs.pi)
      ${shellInit}
    '');

    programs.bash.initExtra = lib.mkIf (shellInit != "") (lib.mkAfter ''
      # Pi coding agent environment (set by programs.pi)
      ${shellInit}
    '');
  };
}
