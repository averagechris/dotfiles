{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.linearCli;
  jsonFormat = pkgs.formats.json {};
  tomlFormat = pkgs.formats.toml {};
  inputPackage =
    if inputs ? linear-cli && inputs.linear-cli ? packages && builtins.hasAttr pkgs.stdenv.hostPlatform.system inputs.linear-cli.packages
    then inputs.linear-cli.packages.${pkgs.stdenv.hostPlatform.system}.linear
    else null;
  linearSkillNames = [
    "linear-admin"
    "linear-data"
    "linear-git"
    "linear-issues"
    "linear-organization"
    "linear-planning"
    "linear-tracking"
  ];
  skillSourceDirectory =
    if cfg.package != null && cfg.package ? src
    then cfg.package.src + "/skills"
    else null;
  linearSkills = builtins.listToAttrs (map (name: {
      inherit name;
      value.source = lib.mkDefault (
        if skillSourceDirectory == null
        then null
        else skillSourceDirectory + "/${name}/SKILL.md"
      );
    })
    linearSkillNames);
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
  # Interpolate so the file is copied into the store with string context. A bare
  # path through toString/escapeShellArg keeps only the virtual source path,
  # which is never materialized under lazy-trees and fails at activation.
  mergeContextScript = "${./merge-context.py}";
  # The CLI resolves its user-level config dir with `dirs::config_dir()`:
  # ~/Library/Application Support/linear-cli on Darwin and
  # $XDG_CONFIG_HOME/linear-cli on Linux. Writing to ~/.config on Darwin
  # produces files the CLI never reads.
  cliConfigDir =
    if pkgs.stdenv.isDarwin
    then "${config.home.homeDirectory}/Library/Application Support/linear-cli"
    else "${config.xdg.configHome}/linear-cli";
  contextConfigPath = "${cliConfigDir}/config.toml";
  hygieneToml = tomlFormat.generate "linear-cli-hygiene.toml" {inherit (cfg) hygiene;};
in {
  imports = [../agent-skills.nix ./hygiene-automation.nix];

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

    hygiene = lib.mkOption {
      type = lib.types.nullOr tomlFormat.type;
      default = {
        apply_ttl = "30m";
        scope = {
          exempt_labels = ["ignore-audit"];
          teams = ["EPD"];
          include_archived = false;
        };
        # Workflow-hygiene rules mirroring the org SDLC conventions
        # (sdlc repo: scripts/linear/rules.py + config/linear/cycles.yaml).
        # Business-day thresholds are approximated as calendar durations
        # (5bd~7d, 3bd~4d, 2bd~3d, 1bd~2d) because the rule engine uses
        # calendar time only. Not expressible in the engine and therefore
        # left to human sweeps: "canceled/duplicate without a comment" and
        # "estimate 8 without sub-issues" (comments and children are not in
        # the entity field model); for projects/initiatives: problem-statement
        # /definition-of-done structure (fragile regexes), KPI presence with
        # its one-sprint grace, theme + commit-type labels on initiatives
        # (confirm actual Linear label-group names before adding
        # missing_group rules), and issue->project->initiative traceability
        # (needs cross-entity joins). Stale GitHub PRs are out of scope for
        # this engine (GitHub PRs are not a hygiene entity); use gh/jj pr
        # sweeps for that.
        rules = [
          {
            id = "issue-missing-domain";
            entity = "issue";
            severity = "medium";
            when = {
              status.not_in = ["Done" "Canceled" "Duplicate"];
              labels.missing_group = "domain";
            };
          }
          {
            id = "issue-missing-type";
            entity = "issue";
            severity = "medium";
            when = {
              status.not_in = ["Done" "Canceled" "Duplicate"];
              labels.missing_group = "type";
            };
          }
          {
            id = "missing-priority";
            entity = "issue";
            severity = "medium";
            when = {
              status.not_in = ["Done" "Canceled" "Duplicate"];
              priority.missing = true;
            };
          }
          {
            id = "unassigned-active";
            entity = "issue";
            severity = "high";
            when = {
              status."in" = ["Todo" "Spec" "Ready" "In Progress" "In Review" "QA"];
              assignee.missing = true;
            };
          }
          {
            id = "missing-estimate-in-cycle";
            entity = "issue";
            severity = "medium";
            when = {
              status.not_in = ["Done" "Canceled" "Duplicate"];
              cycle.missing = false;
              estimate.missing = true;
            };
          }
          # Estimates follow the fibonacci scale {0,1,2,3,5,8}; numeric
          # predicates have no set-membership operator, so the off-scale
          # values get one rule each.
          {
            id = "estimate-nonstandard-4";
            entity = "issue";
            severity = "low";
            when.estimate.eq = 4;
          }
          {
            id = "estimate-nonstandard-6";
            entity = "issue";
            severity = "low";
            when.estimate.eq = 6;
          }
          {
            id = "estimate-nonstandard-7";
            entity = "issue";
            severity = "low";
            when.estimate.eq = 7;
          }
          {
            id = "estimate-above-scale";
            entity = "issue";
            severity = "medium";
            when.estimate.gt = 8;
          }
          {
            id = "stale-in-progress";
            entity = "issue";
            severity = "medium";
            when = {
              status."in" = ["In Progress"];
              updatedAt.older_than = "7d";
            };
          }
          {
            id = "stale-in-review";
            entity = "issue";
            severity = "high";
            when = {
              status."in" = ["In Review"];
              updatedAt.older_than = "3d";
            };
            fix.options = [
              {
                action = "nudge_review";
                comment = true;
              }
              {
                action = "move_back";
                set.status = "In Progress";
              }
            ];
          }
          {
            id = "stale-qa";
            entity = "issue";
            severity = "medium";
            when = {
              status."in" = ["QA"];
              updatedAt.older_than = "4d";
            };
          }
          {
            id = "stale-ready";
            entity = "issue";
            severity = "low";
            when = {
              status."in" = ["Ready"];
              updatedAt.older_than = "7d";
            };
          }
          # Queued work also goes stale. Todo/Spec after a month means the
          # plan drifted; Backlog gets a quarter before it counts as rot.
          {
            id = "stale-todo";
            entity = "issue";
            severity = "low";
            when = {
              status."in" = ["Todo" "Spec"];
              updatedAt.older_than = "30d";
            };
          }
          {
            id = "stale-backlog";
            entity = "issue";
            severity = "low";
            when = {
              status."in" = ["Backlog"];
              updatedAt.older_than = "90d";
            };
          }
          # Priority-0 and high-priority intake must be triaged within one
          # business day; the two rules are OR branches of "priority <= high".
          {
            id = "triage-sla-unprioritized";
            entity = "issue";
            severity = "high";
            when = {
              status."in" = ["Triage"];
              priority.missing = true;
              createdAt.older_than = "2d";
            };
          }
          {
            id = "triage-sla-high-priority";
            entity = "issue";
            severity = "high";
            when = {
              status."in" = ["Triage"];
              priority.lte = 2;
              createdAt.older_than = "2d";
            };
          }
          # Project rules (sdlc conventions/50_linear/40_entity-usage.md).
          # Project states are lowercase (backlog/planned/started/completed/
          # canceled); initiative states are capitalized (Active/Planned).
          #
          # SDLC: "The creator must set a lead, or the relevant guild lead
          # assigns one within one sprint. Projects without a lead after one
          # sprint are flagged in the audit." Sprints are 1 week
          # (config/linear/cycles.yaml).
          {
            id = "project-missing-lead";
            entity = "project";
            severity = "high";
            when = {
              state.not_in = ["completed" "canceled"];
              lead.missing = true;
              createdAt.older_than = "7d";
            };
          }
          # SDLC: "Project descriptions must start with a problem statement
          # and end with a definition of done." The structure itself would
          # need fragile regexes; only presence is checked.
          {
            id = "project-missing-description";
            entity = "project";
            severity = "medium";
            when = {
              state.not_in = ["completed" "canceled"];
              description.missing = true;
            };
          }
          # SDLC: dates are "encouraged" only; exploratory spikes are exempt
          # from target dates, hence low severity. Planned projects are also
          # expected to carry dates, and anything past planning needs a start
          # date.
          {
            id = "project-started-missing-target-date";
            entity = "project";
            severity = "low";
            when = {
              state."in" = ["planned" "started"];
              targetDate.missing = true;
            };
          }
          {
            id = "project-missing-start-date";
            entity = "project";
            severity = "medium";
            when = {
              state."in" = ["planned" "started"];
              startDate.missing = true;
            };
          }
          # SDLC 70_async-communication: date changes on committed work must
          # be updated + commented, so a past-due target date on a live
          # project is a real violation.
          {
            id = "project-target-date-past";
            entity = "project";
            severity = "high";
            when = {
              state.not_in = ["completed" "canceled"];
              targetDate.past = true;
            };
          }
          # SDLC labels.yaml: "Every project must have exactly one domain
          # project label." missing_group resolves against project labels
          # here; verified to fire on known-unlabeled projects.
          {
            id = "project-missing-domain";
            entity = "project";
            severity = "medium";
            when = {
              state.not_in = ["completed" "canceled"];
              labels.missing_group = "domain";
            };
          }
          # Started projects need a health update every two weeks, matching
          # the initiative cadence; at-risk/off-track projects get a tighter
          # one-week leash.
          {
            id = "project-stale-health";
            entity = "project";
            severity = "medium";
            when = {
              state."in" = ["started"];
              healthUpdatedAt.older_than = "14d";
            };
          }
          {
            id = "project-at-risk-no-update";
            entity = "project";
            severity = "high";
            when = {
              state.not_in = ["completed" "canceled"];
              health."in" = ["atRisk" "offTrack"];
              healthUpdatedAt.older_than = "7d";
            };
          }
          # Initiative rules. SDLC: "Required for active initiatives: All
          # active initiatives must have these fields populated. The audit
          # flags violations." (description, target date, health, linked
          # projects, owner). The workspace currently has zero initiatives,
          # so these are dormant but intentionally present.
          {
            id = "initiative-active-missing-description";
            entity = "initiative";
            severity = "high";
            when = {
              state."in" = ["Active"];
              description.missing = true;
            };
          }
          {
            id = "initiative-active-missing-target-date";
            entity = "initiative";
            severity = "high";
            when = {
              state."in" = ["Active"];
              targetDate.missing = true;
            };
          }
          {
            id = "initiative-active-missing-health";
            entity = "initiative";
            severity = "high";
            when = {
              state."in" = ["Active"];
              health.missing = true;
            };
          }
          {
            id = "initiative-active-missing-owner";
            entity = "initiative";
            severity = "high";
            when = {
              state."in" = ["Active"];
              owner.missing = true;
            };
          }
          {
            id = "initiative-active-no-projects";
            entity = "initiative";
            severity = "high";
            when = {
              state."in" = ["Active"];
              linkedProjects.eq = 0;
            };
          }
          # SDLC anti-pattern: "Active initiatives with no health update for
          # more than 2 weeks are flagged in the audit."
          {
            id = "initiative-stale-health";
            entity = "initiative";
            severity = "medium";
            when = {
              state."in" = ["Active"];
              healthUpdatedAt.older_than = "14d";
            };
          }
        ];
      };
      description = ''
        Contents of the CLI's user-level hygiene.toml `[hygiene]` table
        (apply_ttl, scope, and rules for `linear hygiene check`). The default
        encodes the org SDLC hygiene conventions. Set to null to manage
        hygiene.toml outside Home Manager.
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

    dotfiles.agentSkills = linearSkills;
    dotfiles.agentSkillBundles.linear = {
      sourceDirectory = lib.mkDefault skillSourceDirectory;
      expectedNames = linearSkillNames;
    };

    # hygiene.toml is read-only for the CLI (snoozes and run artifacts live in
    # the state dir), so a store symlink into its config dir is safe.
    home.file."Library/Application Support/linear-cli/hygiene.toml" =
      lib.mkIf (pkgs.stdenv.isDarwin && cfg.hygiene != null) {source = hygieneToml;};
    xdg.configFile."linear-cli/hygiene.toml" =
      lib.mkIf (!pkgs.stdenv.isDarwin && cfg.hygiene != null) {source = hygieneToml;};

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
      ${lib.getExe pkgs.python3Minimal} ${lib.escapeShellArg mergeContextScript} ${lib.escapeShellArg contextJson} ${lib.escapeShellArg contextConfigPath}
    '';
  };
}
