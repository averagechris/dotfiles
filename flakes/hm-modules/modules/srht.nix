{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.srht;
  skillSourceDirectory =
    if cfg.package != null && cfg.package ? src
    then cfg.package.src + "/assets/skills"
    else null;
  system = pkgs.stdenv.hostPlatform.system;
  hasSrhtModule = inputs ? srht && inputs.srht ? homeManagerModules;
  toml = pkgs.formats.toml {};
  inputPackage =
    if inputs ? srht && inputs.srht ? packages && builtins.hasAttr system inputs.srht.packages
    then inputs.srht.packages.${system}.srht or inputs.srht.packages.${system}.default
    else null;

  validationType = lib.types.submodule {
    options = {
      create = lib.mkOption {
        type = lib.types.enum ["off" "warn" "error"];
        default = "off";
      };
      update = lib.mkOption {
        type = lib.types.enum ["off" "warn" "error"];
        default = "off";
      };
      existing = lib.mkOption {
        type = lib.types.enum ["off" "warn" "error"];
        default = "off";
      };
      unknownLabels = lib.mkOption {
        type = lib.types.enum ["off" "warn" "error"];
        default = "off";
      };
    };
  };

  contextLabelType = lib.types.submodule {
    options = {
      name = lib.mkOption {type = lib.types.str;};
      value = lib.mkOption {type = lib.types.str;};
      description = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      addOnCreate = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      filterReads = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      requireOnTracker = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
    };
  };

  groupType = lib.types.submodule {
    options = {
      description = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      values = lib.mkOption {type = lib.types.listOf lib.types.str;};
      min = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.unsigned;
        default = null;
      };
      max = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.unsigned;
        default = null;
      };
      when.anyLabel = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
      };
    };
  };

  policyOptions = {
    contextLabels = lib.mkOption {
      type = lib.types.listOf contextLabelType;
      default = [];
    };
    groups = lib.mkOption {
      type = lib.types.attrsOf groupType;
      default = {};
    };
    knownLabels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
    };
    validation = lib.mkOption {
      type = validationType;
      default = {};
    };
  };
  policyType = lib.types.submodule {options = policyOptions;};
  routePolicyType = lib.types.submodule {
    options =
      policyOptions
      // {
        tracker = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
        project = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
        description = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
      };
  };
  routeType = lib.types.submodule {
    options = {
      name = lib.mkOption {type = lib.types.str;};
      priority = lib.mkOption {
        type = lib.types.int;
        default = 0;
      };
      instance = lib.mkOption {
        type = lib.types.str;
        default = "*";
      };
      owner = lib.mkOption {type = lib.types.str;};
      repo = lib.mkOption {
        type = lib.types.str;
        default = "*";
      };
      policy = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      tracker = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      project = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      description = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
    };
  };

  withoutNulls = lib.filterAttrs (_: value: value != null);
  renderInstance = instance:
    {inherit (instance) name;}
    // lib.optionalAttrs instance.tokenKeyring {token-keyring = true;}
    // lib.optionalAttrs (instance.tokenCmd != null) {token-cmd = instance.tokenCmd;}
    // lib.optionalAttrs (instance.origins != {}) {inherit (instance) origins;};
  renderContextLabel = label:
    withoutNulls {
      inherit (label) name value description;
      add-on-create = label.addOnCreate;
      filter-reads = label.filterReads;
      require-on-tracker = label.requireOnTracker;
    };
  renderGroup = group:
    withoutNulls {
      inherit (group) description values min max;
      when = lib.optionalAttrs (group.when.anyLabel != []) {any-label = group.when.anyLabel;};
    };
  renderPolicy = policy: {
    context-labels = map renderContextLabel policy.contextLabels;
    groups = lib.mapAttrs (_: renderGroup) policy.groups;
    known-labels = policy.knownLabels;
    validation = {
      inherit (policy.validation) create update existing;
      unknown-labels = policy.validation.unknownLabels;
    };
  };
  renderRoutePolicy = policy:
    withoutNulls {
      inherit (policy) tracker project description;
      context-labels = map renderContextLabel policy.contextLabels;
      groups = lib.mapAttrs (_: renderGroup) policy.groups;
      known-labels = policy.knownLabels;
      validation = {
        inherit (policy.validation) create update existing;
        unknown-labels = policy.validation.unknownLabels;
      };
    };
  renderRoute = route:
    withoutNulls {
      inherit (route) name priority instance owner repo policy tracker project description;
    };
  clean = value:
    if builtins.isAttrs value
    then let
      cleaned = lib.mapAttrs (_: clean) value;
    in
      lib.filterAttrs (_: item: item != null && item != {} && item != []) cleaned
    else if builtins.isList value
    then map clean value
    else value;
  renderedConfig = toml.generate "srht-config.toml" ({
      instance = map renderInstance config.programs.srht.instances;
      profiles = lib.mapAttrs (_: clean) config.programs.srht.profiles;
      cache.ttl-minutes = cfg.settings.cache.ttlMinutes;
      scoring = {
        stale-days = cfg.settings.scoring.staleDays;
        label-weights = cfg.settings.scoring.labelWeights;
        status-in-progress = cfg.settings.scoring.statusInProgress;
        assigned-to-me = cfg.settings.scoring.assignedToMe;
        mention-pressure = cfg.settings.scoring.mentionPressure;
        age-per-week = cfg.settings.scoring.agePerWeek;
        recent-activity = cfg.settings.scoring.recentActivity;
      };
      todo-fallback = withoutNulls {
        inherit (cfg.settings.todoFallback) mode tracker;
      };
      route-policies = lib.mapAttrs (_: renderRoutePolicy) cfg.settings.routePolicies;
      routes = map renderRoute cfg.settings.routes;
      todo-policy = renderPolicy cfg.settings.todoPolicy;
    }
    // lib.optionalAttrs (cfg.settings.defaults.tracker != null || cfg.settings.defaults.project != null || cfg.settings.defaults.doneResolution != null) {
      defaults = withoutNulls {
        inherit (cfg.settings.defaults) tracker project;
        done-resolution = cfg.settings.defaults.doneResolution;
      };
    });
in {
  imports = [./agent-skills.nix] ++ lib.optional hasSrhtModule inputs.srht.homeManagerModules.default;

  options.dotfiles.srht = {
    enable = lib.mkEnableOption "srht SourceHut CLI integration";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = inputPackage;
      defaultText = lib.literalExpression ''inputs.srht.packages.${pkgs.stdenv.hostPlatform.system}.srht'';
      description = ''
        srht package to install. Defaults to the srht flake input when the host
        provides it. The package ships bash, fish, and zsh completions under
        share/, so adding it to home.packages installs completions for Home
        Manager-managed shells.
      '';
    };

    activeProfile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "work";
      description = ''
        Named `programs.srht.profiles` entry exported through `SRHT_PROFILE`.
        Set null to require explicit `--profile` selection.
      '';
    };

    settings = {
      cache.ttlMinutes = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 30;
        description = "Todo snapshot cache lifetime in minutes.";
      };

      scoring = {
        staleDays = lib.mkOption {
          type = lib.types.ints.unsigned;
          default = 30;
        };
        labelWeights = lib.mkOption {
          type = lib.types.attrsOf lib.types.number;
          default = {};
        };
        statusInProgress = lib.mkOption {
          type = lib.types.number;
          default = 5.0;
        };
        assignedToMe = lib.mkOption {
          type = lib.types.number;
          default = 3.0;
        };
        mentionPressure = lib.mkOption {
          type = lib.types.number;
          default = 2.0;
        };
        agePerWeek = lib.mkOption {
          type = lib.types.number;
          default = 0.1;
        };
        recentActivity = lib.mkOption {
          type = lib.types.number;
          default = 1.0;
        };
      };

      defaults = {
        tracker = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
        project = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
        doneResolution = lib.mkOption {
          type = lib.types.nullOr (lib.types.enum ["closed" "fixed" "implemented" "wont-fix" "by-design" "invalid" "duplicate" "not-our-bug"]);
          default = null;
          description = "Implicit-profile default resolution for `srht todo done`.";
        };
      };

      todoFallback = {
        mode = lib.mkOption {
          type = lib.types.enum ["template" "error" "disabled"];
          default = "error";
        };
        tracker = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
      };

      routePolicies = lib.mkOption {
        type = lib.types.attrsOf routePolicyType;
        default = {};
        description = "Reusable named todo route policies in srht's current config schema.";
      };

      routes = lib.mkOption {
        type = lib.types.listOf routeType;
        default = [];
        description = "Ordered repository-to-tracker routes.";
      };

      todoPolicy = lib.mkOption {
        type = policyType;
        default = {};
        description = "Optional global todo label policy applied outside a named route policy.";
      };
    };
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !cfg.enable || cfg.package != null;
          message = "dotfiles.srht.enable requires dotfiles.srht.package or an inputs.srht flake input.";
        }
        {
          assertion = !cfg.enable || hasSrhtModule;
          message = "dotfiles.srht.enable requires the srht Home Manager module input to be available.";
        }
        {
          assertion = (cfg.settings.todoFallback.mode == "template") == (cfg.settings.todoFallback.tracker != null);
          message = "dotfiles.srht.settings.todoFallback.tracker must be set exactly when mode is template.";
        }
        {
          assertion = lib.all (route: route.policy == null || builtins.hasAttr route.policy cfg.settings.routePolicies) cfg.settings.routes;
          message = "Every dotfiles.srht.settings.routes policy must name a configured route policy.";
        }
      ];
    }
    (lib.optionalAttrs hasSrhtModule (lib.mkIf cfg.enable {
      programs.srht = {
        enable = true;
        inherit (cfg) package;
        profiles.work = lib.mkDefault {
          instance = "sr.ht";
          tracker = "~averagechris/projects";
          project = "~averagechris/projects";
          done-resolution = "fixed";
          todo-policy = {
            context-labels = [
              {
                name = "repo";
                value = "repo:{repo}";
                description = "Attributes each ticket to its source repository.";
                add-on-create = true;
                filter-reads = true;
                require-on-tracker = true;
              }
            ];
            groups = {
              type = {
                description = "Exactly one conventional-commit-style work type.";
                values = ["chore" "fix" "feature" "security" "docs" "refactor" "perf"];
                min = 1;
                max = 1;
              };
              severity = {
                description = "Exactly one severity on fixes and security work.";
                values = ["severity:critical" "severity:high" "severity:med" "severity:low"];
                min = 1;
                max = 1;
                when.any-label = ["fix" "security"];
              };
              points = {
                description = "Optional Fibonacci estimate; work larger than 13 should be split.";
                values = ["points:1" "points:2" "points:3" "points:5" "points:8" "points:13"];
                max = 1;
              };
            };
            known-labels = ["blocked" "upstream" "duplicate" "wontfix"];
            validation = {
              create = "warn";
              update = "warn";
              existing = "off";
              unknown-labels = "warn";
            };
          };
        };
      };

      home.sessionVariables = lib.optionalAttrs (cfg.activeProfile != null) {
        SRHT_PROFILE = cfg.activeProfile;
      };

      # The upstream module currently renders only instances. Replace that one
      # source value with the complete document while retaining its package and
      # typed instance options, so Home Manager still has a single owner for the
      # config path.
      xdg.configFile."srht/config.toml".source = lib.mkForce renderedConfig;

      dotfiles.agentSkills = {
        srht-issues.source = lib.mkDefault (
          if skillSourceDirectory == null
          then null
          else skillSourceDirectory + "/srht-issues.md"
        );
        srht-ci.source = lib.mkDefault (
          if skillSourceDirectory == null
          then null
          else skillSourceDirectory + "/srht-ci.md"
        );
        srht-setup.source = lib.mkDefault (
          if skillSourceDirectory == null
          then null
          else skillSourceDirectory + "/srht-setup.md"
        );
      };
      dotfiles.agentSkillBundles.srht = {
        sourceDirectory = lib.mkDefault skillSourceDirectory;
        layout = "flat-markdown";
        expectedNames = ["srht-ci" "srht-issues" "srht-setup"];
      };
    }))
  ];
}
