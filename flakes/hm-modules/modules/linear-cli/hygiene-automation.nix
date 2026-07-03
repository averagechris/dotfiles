{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.linearCli;
  acfg = cfg.hygieneAutomation;

  # Mirrors the CLI config dir resolution in ./default.nix (dirs::config_dir()).
  cliConfigDir =
    if pkgs.stdenv.isDarwin
    then "${config.home.homeDirectory}/Library/Application Support/linear-cli"
    else "${config.xdg.configHome}/linear-cli";
  artifactPath = "${cliConfigDir}/state/${acfg.profile}/hygiene-last-run.json";
  stateDir = "${config.home.homeDirectory}/.local/state/linear-hygiene";
  logDir = "${config.home.homeDirectory}/Library/Logs";

  supportedAutofixRules = [
    "issue-missing-domain"
    "issue-missing-type"
    "missing-estimate-in-cycle"
    "missing-priority"
  ];

  estimationGuidance =
    lib.attrByPath ["issue_create" "estimation" "guidance"] "" cfg.context;

  timeType = lib.types.submodule {
    options = {
      hour = lib.mkOption {
        type = lib.types.ints.between 0 23;
        description = "Hour of day (0-23).";
      };
      minute = lib.mkOption {
        type = lib.types.ints.between 0 59;
        default = 0;
        description = "Minute of hour (0-59).";
      };
    };
  };

  weekdayTimes = times:
    lib.concatMap (
      weekday:
        map (time: {
          Weekday = weekday;
          Hour = time.hour;
          Minute = time.minute;
        })
        times
    )
    acfg.weekdays;

  notifyScript = pkgs.writeShellApplication {
    name = "linear-hygiene-notify";
    runtimeInputs = [pkgs.python3];
    text = ''
      export LINEAR_HYGIENE_ARTIFACT=${lib.escapeShellArg artifactPath}
      export LINEAR_HYGIENE_STATE_DIR=${lib.escapeShellArg stateDir}
      exec python3 ${./hygiene_notify.py} "$@"
    '';
  };

  refreshScript = pkgs.writeShellApplication {
    name = "linear-hygiene-refresh";
    runtimeInputs = [cfg.package];
    text = ''
      linear --quiet --retry 3 --no-pager hygiene check \
        ${lib.escapeShellArgs acfg.scopeArgs} --output json >/dev/null
      case "''${1:-}" in
        --notify-summary) exec ${lib.getExe notifyScript} summary ;;
        --notify-new-high) exec ${lib.getExe notifyScript} new-high ;;
        *) ;;
      esac
    '';
  };

  promptScript = pkgs.writeShellApplication {
    name = "linear-hygiene-prompt";
    runtimeInputs = [pkgs.jq];
    text = ''
      artifact=${lib.escapeShellArg artifactPath}
      [ -f "$artifact" ] || exit 1
      counts="$(jq -r '
        [.findings[]? | select(.resolved | not) | .severity]
        | "\(map(select(. == "high")) | length) \(map(select(. == "medium")) | length)"
      ' "$artifact" 2>/dev/null)" || exit 1
      high="''${counts%% *}"
      medium="''${counts##* }"
      case "''${1:-hint}" in
        check)
          [ "$high" -gt 0 ] || [ "$medium" -gt 0 ]
          ;;
        *)
          out=""
          [ "$high" -gt 0 ] && out="⚑$high"
          [ "$medium" -gt 0 ] && out="$out''${out:+ }~$medium"
          printf '%s' "$out"
          ;;
      esac
    '';
  };

  greetingScript = pkgs.writeShellApplication {
    name = "linear-hygiene-greeting";
    runtimeInputs = [pkgs.python3];
    text = ''
      export LINEAR_HYGIENE_ARTIFACT=${lib.escapeShellArg artifactPath}
      export LINEAR_HYGIENE_STATE_DIR=${lib.escapeShellArg stateDir}
      export LINEAR_HYGIENE_GREETING_INTERVAL=${toString acfg.shell.greeting.minIntervalMinutes}
      exec python3 ${./hygiene_greeting.py}
    '';
  };

  autofixScript = pkgs.writeShellApplication {
    name = "linear-hygiene-autofix";
    runtimeInputs = [cfg.package pkgs.python3];
    text = ''
      # launchd starts agents with a minimal PATH; the agent harness
      # (opencode today, maybe pi later) is installed via Home Manager, so add
      # the user profile bins for the agentCommand lookup.
      export PATH="/etc/profiles/per-user/$USER/bin:$HOME/.nix-profile/bin:$PATH"
      export LINEAR_HYGIENE_ARTIFACT=${lib.escapeShellArg artifactPath}
      export LINEAR_HYGIENE_STATE_DIR=${lib.escapeShellArg stateDir}
      export LINEAR_HYGIENE_SCOPE_ARGS=${lib.escapeShellArg (builtins.toJSON acfg.scopeArgs)}
      export LINEAR_HYGIENE_AUTOFIX_RULES=${lib.escapeShellArg (builtins.toJSON acfg.autofix.rules)}
      export LINEAR_HYGIENE_AUTOFIX_MAX=${toString acfg.autofix.maxFindings}
      export LINEAR_HYGIENE_AGENT_CMD=${lib.escapeShellArg (builtins.toJSON acfg.autofix.agentCommand)}
      export LINEAR_HYGIENE_ESTIMATION_GUIDANCE=${lib.escapeShellArg estimationGuidance}
      exec python3 ${./hygiene_autofix.py} "$@"
    '';
  };

  mkAgent = {
    args,
    calendar,
    logName,
  }: {
    enable = true;
    config = {
      ProgramArguments = args;
      StartCalendarInterval = calendar;
      ProcessType = "Background";
      LowPriorityIO = true;
      StandardOutPath = "${logDir}/${logName}.log";
      StandardErrorPath = "${logDir}/${logName}.log";
    };
  };
in {
  options.dotfiles.linearCli.hygieneAutomation = {
    enable = lib.mkEnableOption ''
      Linear hygiene automation: scheduled report-cache refreshes,
      macOS notifications, shell/prompt nudges, and an agentic autofix job
    '';

    profile = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "default";
      description = "Linear CLI profile whose hygiene check artifact is used.";
    };

    scopeArgs = lib.mkOption {
      type = lib.types.listOf lib.types.nonEmptyStr;
      default = ["--mine"];
      description = "Scope arguments passed to `linear hygiene check` runs.";
    };

    weekdays = lib.mkOption {
      type = lib.types.listOf (lib.types.ints.between 0 7);
      default = [1 2 3 4 5];
      description = "launchd Weekday values on which scheduled jobs run.";
    };

    refresh.times = lib.mkOption {
      type = lib.types.listOf timeType;
      default = [
        {
          hour = 10;
          minute = 0;
        }
        {
          hour = 16;
          minute = 0;
        }
      ];
      description = "Times of day to refresh the hygiene report cache.";
    };

    summaryNotification = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Send a macOS notification when unresolved high or medium findings
          exist, shortly after the afternoon refresh.
        '';
      };

      time = lib.mkOption {
        type = timeType;
        default = {
          hour = 16;
          minute = 5;
        };
        description = ''
          When to send the daily summary notification. Should trail a refresh
          time so it reads a fresh artifact.
        '';
      };
    };

    watch = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Hourly work-hours watch that re-checks hygiene and notifies about
          high-severity findings not previously seen (deduplicated locally).
        '';
      };

      startHour = lib.mkOption {
        type = lib.types.ints.between 0 23;
        default = 9;
        description = "First hour of day the watch runs.";
      };

      endHour = lib.mkOption {
        type = lib.types.ints.between 0 23;
        default = 18;
        description = "Last hour of day the watch runs.";
      };

      minute = lib.mkOption {
        type = lib.types.ints.between 0 59;
        default = 30;
        description = ''
          Minute offset for watch runs; the default of 30 avoids colliding
          with on-the-hour refresh and autofix runs.
        '';
      };
    };

    autofix = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Schedule the agentic autofix job that silently resolves low-stakes
          findings (labels, estimates, priority). The
          `linear-hygiene-autofix` command is installed for manual runs
          regardless.
        '';
      };

      times = lib.mkOption {
        type = lib.types.listOf timeType;
        default = [
          {
            hour = 10;
            minute = 20;
          }
          {
            hour = 16;
            minute = 20;
          }
        ];
        description = ''
          When the autofix job runs. Defaults trail the refresh times so it
          reads a fresh artifact.
        '';
      };

      rules = lib.mkOption {
        type = lib.types.listOf (lib.types.enum supportedAutofixRules);
        default = supportedAutofixRules;
        description = ''
          Hygiene rule ids the agent may resolve. Only low-stakes rules with
          validated, bounded fixes are supported.
        '';
      };

      maxFindings = lib.mkOption {
        type = lib.types.ints.positive;
        default = 8;
        description = "Maximum findings handled per autofix run.";
      };

      agentCommand = lib.mkOption {
        type = lib.types.listOf lib.types.nonEmptyStr;
        default = [
          "opencode"
          "run"
          "--model"
          "openrouter/openai/gpt-5.5"
          "--variant"
          "low"
          "--title"
          "linear-hygiene-autofix"
        ];
        description = ''
          Agent harness command; the batched decision prompt is appended as
          the final argument. The agent only proposes decisions - the autofix
          script validates them against allowed values and applies updates
          via the linear CLI. Swap in a different harness (for example pi)
          by overriding this list.
        '';
      };
    };

    shell = {
      promptHint.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Show a compact starship prompt hint (for example "⚑1 ~3") while
          unresolved high/medium findings exist in the local artifact.
        '';
      };

      greeting = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Print a small fun hygiene report when opening a new interactive
            zsh shell and unresolved high/medium findings exist. Disable at
            runtime with LINEAR_HYGIENE_GREETING=0.
          '';
        };

        minIntervalMinutes = lib.mkOption {
          type = lib.types.ints.unsigned;
          default = 1;
          description = ''
            Minimum minutes between greeting printouts (0 prints on every new
            shell). The default only suppresses repeats within the same
            minute, such as a burst of tmux panes.
          '';
        };
      };
    };
  };

  config = lib.mkIf (cfg.enable && acfg.enable) {
    assertions = [
      {
        assertion = pkgs.stdenv.isDarwin;
        message = "dotfiles.linearCli.hygieneAutomation is currently supported only on Darwin (launchd + osascript).";
      }
    ];

    home.packages = [
      refreshScript
      notifyScript
      autofixScript
      greetingScript
      promptScript
    ];

    launchd.agents = lib.mkMerge [
      {
        linear-hygiene-refresh = mkAgent {
          args = [(lib.getExe refreshScript)];
          calendar = weekdayTimes acfg.refresh.times;
          logName = "linear-hygiene-refresh";
        };
      }
      (lib.mkIf acfg.summaryNotification.enable {
        linear-hygiene-summary = mkAgent {
          args = [(lib.getExe notifyScript) "summary"];
          calendar = weekdayTimes [acfg.summaryNotification.time];
          logName = "linear-hygiene-summary";
        };
      })
      (lib.mkIf acfg.watch.enable {
        linear-hygiene-watch = mkAgent {
          args = [(lib.getExe refreshScript) "--notify-new-high"];
          calendar = weekdayTimes (
            map (hour: {
              inherit hour;
              inherit (acfg.watch) minute;
            })
            (lib.range acfg.watch.startHour acfg.watch.endHour)
          );
          logName = "linear-hygiene-watch";
        };
      })
      (lib.mkIf acfg.autofix.enable {
        linear-hygiene-autofix = mkAgent {
          args = [(lib.getExe autofixScript)];
          calendar = weekdayTimes acfg.autofix.times;
          logName = "linear-hygiene-autofix";
        };
      })
    ];

    programs.starship.settings.custom.linear_hygiene = lib.mkIf acfg.shell.promptHint.enable {
      description = "Linear hygiene findings hint";
      shell = [(lib.getExe promptScript)];
      use_stdin = false;
      when = "check";
      command = "hint";
      format = "[$output]($style) ";
      style = "bold yellow";
    };

    programs.zsh.initContent = lib.mkIf acfg.shell.greeting.enable (lib.mkAfter ''
      ${lib.getExe greetingScript} || true
    '');
  };
}
