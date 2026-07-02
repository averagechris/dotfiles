{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.linearCli;
  jsonFormat = pkgs.formats.json {};
  inputPackage =
    if inputs ? linear-cli && inputs.linear-cli ? packages && builtins.hasAttr pkgs.stdenv.hostPlatform.system inputs.linear-cli.packages
    then inputs.linear-cli.packages.${pkgs.stdenv.hostPlatform.system}.linear
    else null;
  contextJson = jsonFormat.generate "linear-cli-context.json" cfg.context;
  linearCompletions = pkgs.runCommand "linear-cli-completions" {} ''
    install -dm755 \
      $out/share/bash-completion/completions \
      $out/share/fish/vendor_completions.d \
      $out/share/zsh/site-functions

    ${lib.getExe cfg.package} completions static bash > $out/share/bash-completion/completions/linear
    ${lib.getExe cfg.package} completions static fish > $out/share/fish/vendor_completions.d/linear.fish
    ${lib.getExe cfg.package} completions static zsh > $out/share/zsh/site-functions/_linear
  '';
  mergeContextScript = pkgs.writeText "linear-cli-merge-context.py" ''
    import json
    import os
    import re
    import stat
    import sys
    import tomllib

    context_path, config_path = sys.argv[1:3]

    with open(context_path, "r", encoding="utf-8") as handle:
        desired_context = json.load(handle)

    data = {}
    if os.path.exists(config_path):
        with open(config_path, "rb") as handle:
            data = tomllib.load(handle)

    # Match the CLI's on-disk secret hygiene: auth tokens live in the OS
    # keyring, not in the config file. Preserve workspace/profile metadata, but
    # never re-emit legacy plaintext secrets if an old config still contains
    # them.
    data.pop("api_key", None)
    for workspace in data.get("workspaces", {}).values():
        if isinstance(workspace, dict):
            workspace["api_key"] = ""
            oauth = workspace.get("oauth")
            if isinstance(oauth, dict):
                oauth.pop("access_token", None)
                oauth.pop("refresh_token", None)

    data["context"] = desired_context

    bare_key = re.compile(r"^[A-Za-z0-9_-]+$")

    def quote_string(value):
        return json.dumps(value, ensure_ascii=False)

    def key_segment(key):
        return key if bare_key.match(key) else quote_string(key)

    def scalar(value):
        if isinstance(value, bool):
            return "true" if value else "false"
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            return repr(float(value)) if isinstance(value, float) else str(value)
        if isinstance(value, str):
            return quote_string(value)
        raise TypeError(f"unsupported TOML scalar: {value!r}")

    def inline_table(mapping):
        parts = []
        for key in sorted(mapping):
            value = mapping[key]
            if isinstance(value, dict):
                rendered = inline_table(value)
            elif isinstance(value, list):
                rendered = array(value)
            elif value is None:
                continue
            else:
                rendered = scalar(value)
            parts.append(f"{key_segment(key)} = {rendered}")
        return "{ " + ", ".join(parts) + " }"

    def array(values):
        if all(not isinstance(value, dict) for value in values):
            return "[" + ", ".join(scalar(value) for value in values) + "]"
        return "[" + ", ".join(inline_table(value) for value in values) + "]"

    def emit_table(lines, prefix, mapping):
        scalar_items = []
        child_tables = []
        array_tables = []

        for key in sorted(mapping):
            value = mapping[key]
            if value is None:
                continue
            if isinstance(value, dict):
                child_tables.append((key, value))
            elif isinstance(value, list) and any(isinstance(item, dict) for item in value):
                array_tables.append((key, value))
            else:
                scalar_items.append((key, value))

        if prefix:
            lines.append(f"[{'.'.join(key_segment(part) for part in prefix)}]")
        for key, value in scalar_items:
            lines.append(f"{key_segment(key)} = {array(value) if isinstance(value, list) else scalar(value)}")
        if scalar_items and (child_tables or array_tables):
            lines.append("")

        for index, (key, value) in enumerate(child_tables):
            emit_table(lines, prefix + [key], value)
            if index != len(child_tables) - 1 or array_tables:
                lines.append("")

        for table_index, (key, values) in enumerate(array_tables):
            for value_index, value in enumerate(values):
                lines.append(f"[[{'.'.join(key_segment(part) for part in prefix + [key])}]]")
                emit_table(lines, [], value)
                if value_index != len(values) - 1:
                    lines.append("")
            if table_index != len(array_tables) - 1:
                lines.append("")

    lines = []
    top_scalars = {key: value for key, value in data.items() if key != "context" and not isinstance(value, dict) and value is not None}
    for key in sorted(top_scalars):
        lines.append(f"{key_segment(key)} = {array(top_scalars[key]) if isinstance(top_scalars[key], list) else scalar(top_scalars[key])}")
    if top_scalars:
        lines.append("")

    for key in sorted(key for key in data if key != "context" and isinstance(data[key], dict)):
        emit_table(lines, [key], data[key])
        lines.append("")

    emit_table(lines, ["context"], data["context"])
    content = "\n".join(lines).rstrip() + "\n"

    os.makedirs(os.path.dirname(config_path), exist_ok=True)
    tmp_path = os.path.join(os.path.dirname(config_path), ".config.toml.tmp")
    with open(tmp_path, "w", encoding="utf-8") as handle:
        handle.write(content)
    os.chmod(tmp_path, stat.S_IRUSR | stat.S_IWUSR)
    os.replace(tmp_path, config_path)
  '';
  contextConfigPath = "${config.xdg.configHome}/linear-cli/config.toml";
in {
  options.dotfiles.linearCli = {
    enable = lib.mkEnableOption "Linear CLI with user/org context for agents";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = inputPackage;
      defaultText = lib.literalExpression ''inputs.linear-cli.packages.${pkgs.stdenv.hostPlatform.system}.linear'';
      description = ''
        Linear CLI package to install. Defaults to the linear-cli flake input
        when the host provides it.
      '';
    };

    completions.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install generated static Linear shell completions in the standard Home
        Manager profile completion directories for enabled shells.
      '';
    };

    context = lib.mkOption {
      inherit (jsonFormat) type;
      default = {
        version = 1;
        defaults = {
          team = "EPD";
          status = "Backlog";
        };
        issue_create = {
          on_ambiguity = "ask";
          fields = {
            team = {
              mode = "default";
              required = true;
            };
            status = {
              mode = "infer_or_ask";
              required = true;
              guidance = "Default to Backlog for newly created planned work. If the user clearly says they are going to work on it now, set status to In Progress and assign it to me. Ask when intent is ambiguous.";
            };
            priority = {
              mode = "infer_or_ask";
              required = true;
              guidance = "Every non-terminal issue needs priority 1-4. Use 0 only for unclassified intake that needs triage or guild evaluation; when uncertain, ask.";
            };
            project = {
              mode = "infer_or_ask";
              discovery = "projects";
              guidance = "Use projects for time-bound deliverables with a clear outcome. Do not create projects for single small issues or ongoing domain maintenance; fetch options and ask when ambiguous.";
            };
            initiative = {
              mode = "infer_or_ask";
              discovery = "initiatives";
              guidance = "Use initiatives only for strategic efforts. Issues trace through Initiative -> Project -> Issue; bugs and small tactical work can remain initiative-less. Do not guess.";
            };
            estimate = {
              mode = "infer_or_ask";
              required_when = "before_cycle";
              guidance_ref = "issue_create.estimation";
            };
            assignee = {
              mode = "infer_or_ask";
              required_when = "before_cycle";
              guidance = "Assignee is required before an issue enters a cycle. If the user clearly says they are going to work on a newly created issue now, assign it to me; otherwise ask instead of guessing ownership.";
            };
          };
          estimation = {
            scale = "fibonacci";
            values = [0.0 1.0 2.0 3.0 5.0 8.0];
            guidance = "Estimate complexity and uncertainty, not hours. 0=tracking/roll-up, 1=tiny, 2=small, 3=medium, 5=large, 8=split into smaller issues. Estimates are required before cycle work; ask when uncertain.";
          };
        };
        label_groups = [
          {
            key = "domain";
            linear_group = "domain";
            required = true;
            cardinality = "exactly_one";
            mode = "infer_or_ask";
            ask_prompt = "Which domain label best matches this work?";
            guidance = "Every issue must have exactly one domain label. Infer only when clear from the repo, files, or request; otherwise fetch options and ask.";
          }
          {
            key = "type";
            linear_group = "type";
            required = true;
            cardinality = "exactly_one";
            mode = "infer_or_ask";
            ask_prompt = "Which type label best matches this work?";
            guidance = "Every issue must have exactly one type label: bug, feature, chore, or documentation. Infer only when clear; otherwise ask.";
          }
          {
            key = "execution";
            linear_group = "execution";
            required = false;
            cardinality = "at_most_one";
            mode = "default";
            default = "agentic";
            ask_prompt = "Will this be executed agentically or traditionally?";
            guidance = "Default agent-created issues to agentic. Use traditional when the owner intends to work without an agent; do not create new execution labels.";
          }
          {
            key = "lob";
            linear_group = "lob";
            required = false;
            cardinality = "many";
            mode = "suggest";
            ask_prompt = "Any line-of-business labels to apply?";
            guidance = "Suggest existing line-of-business labels only when they are clearly relevant; do not invent labels.";
          }
          {
            key = "carrier";
            linear_group = "carrier";
            required = false;
            cardinality = "many";
            mode = "suggest";
            ask_prompt = "Any carrier or partner labels to apply?";
            guidance = "Suggest existing carrier or partner labels only when they are clearly relevant; do not invent labels.";
          }
        ];
        cache.ttl = {
          teams = "7d";
          statuses = "7d";
          labels = "7d";
          projects = "6h";
          initiatives = "24h";
        };
        agent_instructions = [
          "Default to the EPD team and Backlog status for newly identified planned work unless the user specifies otherwise."
          "If the user clearly indicates they are creating an issue to work on right now, assign it to me and set status to In Progress instead of Backlog."
          "Use Triage for urgent unplanned work and Backlog for accepted-but-unscheduled planned work; move to Spec only when a spec is actively being written or reviewed."
          "Do not invent projects, initiatives, labels, statuses, or owners; use `linear context options ... --output json --compact` and ask when ambiguous."
          "After creating or changing projects, labels, statuses, or teams, refresh the relevant context cache before relying on option discovery in the same session. For example: `linear context refresh projects --quiet --retry 3`."
          "For pre-existing implementation work, issues should normally be Ready before starting. Newly created personal immediate-work issues may start in In Progress when the user's intent is clear. Humans handle QA/Done after verification."
          "New agent-created discovered-work issues should be clear, imperative, linked to the parent context when applicable, and limited to a small number per session."
        ];
      };
      description = ''
        Non-secret Linear CLI context merged into ~/.config/linear-cli/config.toml.
        This mirrors `linear context suggest` output and can be overridden by
        repository-local .linear.toml files.
      '';
    };

    cacheRefresh = {
      enable = lib.mkEnableOption "periodic Linear context option cache refresh";

      intervalSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 86400;
        description = ''
          Number of seconds between background `linear context refresh` runs. On
          macOS, launchd does not wake a sleeping laptop to run the job.
        '';
      };

      resources = lib.mkOption {
        type = lib.types.listOf lib.types.nonEmptyStr;
        default = ["labels" "projects" "initiatives" "statuses" "teams"];
        description = ''
          Context cache resources to refresh. Use names accepted by
          `linear context refresh`; an empty list lets the CLI refresh all known
          resources.
        '';
      };

      retry = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 3;
        description = "Number of Linear CLI API retries for background refreshes.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.package != null;
        message = "dotfiles.linearCli.enable requires dotfiles.linearCli.package or an inputs.linear-cli flake input.";
      }
      {
        assertion = !cfg.cacheRefresh.enable || pkgs.stdenv.isDarwin;
        message = "dotfiles.linearCli.cacheRefresh.enable is currently supported only on Darwin via launchd.";
      }
    ];

    home.packages = [cfg.package] ++ lib.optional cfg.completions.enable linearCompletions;

    launchd.agents.linear-cli-context-refresh = lib.mkIf (cfg.cacheRefresh.enable && pkgs.stdenv.isDarwin) {
      enable = true;
      config = {
        ProgramArguments =
          [
            (lib.getExe cfg.package)
            "--quiet"
            "--retry"
            (toString cfg.cacheRefresh.retry)
            "context"
            "refresh"
          ]
          ++ cfg.cacheRefresh.resources;
        StartInterval = cfg.cacheRefresh.intervalSeconds;
        ProcessType = "Background";
        LowPriorityIO = true;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/linear-cli-context-refresh.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/linear-cli-context-refresh.log";
      };
    };

    home.activation.linear-cli-context = lib.hm.dag.entryAfter ["writeBoundary" "installPackages"] ''
      ${lib.getExe pkgs.python3} ${lib.escapeShellArg mergeContextScript} ${lib.escapeShellArg contextJson} ${lib.escapeShellArg contextConfigPath}
    '';
  };
}
