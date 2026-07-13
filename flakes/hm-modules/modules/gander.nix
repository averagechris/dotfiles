{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.gander;
  skillSourceDirectory =
    if cfg.package != null && cfg.package ? src
    then cfg.package.src + "/skills"
    else null;
  tomlFormat = pkgs.formats.toml {};
  system = pkgs.stdenv.hostPlatform.system;
  inputPackage =
    if inputs ? gander && inputs.gander ? packages && builtins.hasAttr system inputs.gander.packages
    then inputs.gander.packages.${system}.gander or inputs.gander.packages.${system}.default
    else null;

  nullable = type: description:
    lib.mkOption {
      type = lib.types.nullOr type;
      default = null;
      inherit description;
    };
  nullableString = description: nullable lib.types.str description;
  nullableBool = description: nullable lib.types.bool description;
  nullableUnsigned = description: nullable lib.types.ints.unsigned description;
  nullableStrings = description: nullable (lib.types.listOf lib.types.str) description;
  nullableEnum = values: description: nullable (lib.types.enum values) description;
  withoutNulls = lib.filterAttrs (_: value: value != null);

  keybindingNames = [
    "quit"
    "help"
    "summon-agent"
    "yank-handoff"
    "move-down"
    "move-up"
    "toggle-focus"
    "diff-top"
    "diff-bottom"
    "compare-trunk"
    "compare-parent"
    "target-chooser"
    "revset-input"
    "stack-next"
    "stack-previous"
    "operation-picker"
    "jj-helpers"
    "next-unviewed"
    "previous-unviewed"
    "next-comment"
    "previous-comment"
    "file-search"
    "symbol-outline"
    "next-symbol"
    "previous-symbol"
    "next-changed-hunk"
    "previous-changed-hunk"
    "toggle-large-diff"
    "toggle-agent-order"
    "flag-list"
    "open-work"
    "activity"
    "walkthrough-list"
    "zen"
    "draft-list"
    "scroll-down"
    "scroll-up"
    "scroll-diff-left"
    "scroll-diff-right"
    "mark-viewed"
    "toggle-viewed"
    "mark-all-viewed"
    "toggle-generated"
    "cycle-viewed-filter"
    "toggle-fold"
    "collapse-fold"
    "expand-fold"
    "toggle-context-fold"
    "expand-context"
    "expand-context-all"
    "collapse-context"
    "view-options"
    "toggle-word-highlight"
    "toggle-line-background"
    "toggle-gutter-bar"
    "toggle-diff-wrap"
    "toggle-file-pane"
    "toggle-diff-view"
    "range-comment"
    "mark-walkthrough"
    "cancel-range-comment"
    "comment"
    "cycle-comment-state"
    "edit-comment"
    "delete-comment"
    "comment-list"
    "comment-list-new-general"
    "comment-list-ready"
    "comment-list-cycle-action"
    "comment-list-cycle-kind"
    "submit-comment"
    "cancel-comment"
    "insert-newline"
    "delete-char"
    "target-picker-down"
    "target-picker-up"
    "popup-move-down"
    "popup-move-up"
    "popup-select"
    "popup-toggle"
    "popup-close"
    "popup-close-q"
    "draft-accept"
    "draft-edit"
    "draft-discard"
    "walkthrough-delete"
    "walkthrough-move-down"
    "walkthrough-move-up"
    "zen-next"
    "zen-previous"
    "zen-toggle-view"
    "zen-glance"
    "zen-artifact"
    "zen-toggle-details"
    "zen-refocus"
    "zen-acknowledge"
    "zen-artifact-next"
    "zen-artifact-previous"
  ];
  keybindingOptions = builtins.listToAttrs (map (name: {
      inherit name;
      value = nullableStrings "Keys bound to Gander's `${name}` action; an empty list unbinds configurable keys.";
    })
    keybindingNames);

  styleOptions = names:
    builtins.listToAttrs (map (name: {
        inherit name;
        value = nullableString "Gander terminal style for `${name}`.";
      })
      names);

  syntaxMappingType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Built-in syntax language name.";
      };
      extensions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Additional filename extensions for this language.";
      };
      filenames = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Additional exact filenames for this language.";
      };
    };
  };

  # This is the complete, collision-free Colemak Mod-DH override documented and
  # regression-tested by Gander. It must remain atomic: partial application
  # collides with normal, popup, draft, comment-center, and zen actions.
  colemakKeybindings = {
    move-down = ["n" "down"];
    move-up = ["e" "up"];
    next-unviewed = ["alt-j"];
    previous-unviewed = ["J"];
    edit-comment = ["alt-e"];
    popup-move-down = ["n" "down"];
    popup-move-up = ["e" "up"];
    comment-list-new-general = ["ctrl-n"];
    draft-edit = ["alt-e"];
    zen-artifact = ["i"];
    zen-next = ["enter" "right" "space"];
  };

  defaultSettings = {
    # Keep agent invocation explicit: automatic startup is surprising on every
    # host, while `@` remains a cheap opt-in from inside a review.
    agent.command = "opencode run --model openrouter/openai/gpt-5.5 --variant low";
    comments.initial-state = "todo";
    diff.soft-wrap = true;
    generated.presets = ["lockfiles"];
    keybindings = colemakKeybindings;
  };

  typedSettings = lib.filterAttrs (_: value: value != {}) {
    ignore = withoutNulls {
      inherit (cfg.config.ignore) globs;
    };
    jj = withoutNulls {
      inherit (cfg.config.jj) binary;
    };
    artifact = withoutNulls {
      inherit (cfg.config.artifact) format profile basename;
      output_dir = cfg.config.artifact.outputDir;
      on_tui_quit = cfg.config.artifact.onTuiQuit;
    };
    generated = withoutNulls {
      inherit (cfg.config.generated) presets globs;
    };
    syntax =
      withoutNulls {
        inherit (cfg.config.syntax) enabled languages mappings;
      }
      // lib.optionalAttrs (withoutNulls cfg.config.syntax.theme != {}) {
        theme = withoutNulls cfg.config.syntax.theme;
      };
    limits = withoutNulls {
      max-diff-lines = cfg.config.limits.maxDiffLines;
      nudge-diff-lines = cfg.config.limits.nudgeDiffLines;
      nudge-files = cfg.config.limits.nudgeFiles;
    };
    agent = withoutNulls {
      inherit (cfg.config.agent) command autostart prompt;
    };
    diff =
      withoutNulls {
        word-highlight = cfg.config.diff.wordHighlight;
        line-background = cfg.config.diff.lineBackground;
        gutter-bar = cfg.config.diff.gutterBar;
        inherit (cfg.config.diff) view;
        soft-wrap = cfg.config.diff.softWrap;
        context-step = cfg.config.diff.contextStep;
      }
      // lib.optionalAttrs (withoutNulls cfg.config.diff.theme != {}) {
        theme = withoutNulls cfg.config.diff.theme;
      };
    comments = withoutNulls {
      initial-state = cfg.config.comments.initialState;
    };
    keybindings = withoutNulls cfg.config.keybindings;
  };

  # Precedence is intentional and stable: shared defaults, typed options, then
  # the format-typed raw escape hatch.
  mergedSettings = lib.recursiveUpdate (lib.recursiveUpdate defaultSettings typedSettings) cfg.settings;
in {
  imports = [./agent-skills.nix];

  options.dotfiles.gander = {
    enable = lib.mkEnableOption "Gander jj review TUI";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = inputPackage;
      defaultText = lib.literalExpression ''inputs.gander.packages.${pkgs.stdenv.hostPlatform.system}.gander'';
      description = "Gander CLI package to install; defaults to the Gander flake input.";
    };

    config = {
      ignore.globs = nullableStrings "File globs removed from the visible diff.";
      jj.binary = nullableString "Path or command name for the Jujutsu executable.";

      artifact = {
        format = nullableEnum ["json" "markdown" "html"] "Default artifact format.";
        profile = nullableEnum ["human" "agent"] "Default artifact detail profile.";
        outputDir = nullableString "Artifact output directory (rendered as `output_dir`).";
        basename = nullableString "Artifact filename without its format extension.";
        onTuiQuit = nullableEnum ["never" "write" "stdout"] "Artifact behavior when the TUI exits (rendered as `on_tui_quit`).";
      };

      generated = {
        presets = nullable (lib.types.listOf (lib.types.enum ["lockfiles" "api-clients" "vendored-assets"])) "Generated-file preset names.";
        globs = nullableStrings "Additional generated-file globs.";
      };

      syntax = {
        enabled = nullableBool "Enable syntax highlighting.";
        languages = nullableStrings "Allow-list of built-in syntax language names.";
        mappings = nullable (lib.types.listOf syntaxMappingType) "Additional filename-to-language mappings.";
        theme = styleOptions [
          "attribute"
          "comment"
          "constant"
          "function"
          "keyword"
          "number"
          "operator"
          "property"
          "punctuation"
          "string"
          "type"
          "variable"
        ];
      };

      limits = {
        maxDiffLines = nullableUnsigned "Changed-line limit before Gander initially collapses a large diff.";
        nudgeDiffLines = nullableUnsigned "Changed-line threshold for the agent-review nudge; zero disables it.";
        nudgeFiles = nullableUnsigned "Changed-file threshold for the agent-review nudge; zero disables it.";
      };

      agent = {
        command = nullableString "Shell command used to summon an agent.";
        autostart = nullableBool "Start the configured agent when the TUI opens.";
        prompt = nullableString "Agent prompt template; supports `{repo}`, `{base}`, and `{rev}`.";
      };

      diff = {
        wordHighlight = nullableBool "Highlight changed words within changed lines.";
        lineBackground = nullableBool "Color changed line backgrounds.";
        gutterBar = nullableBool "Show a colored gutter bar.";
        view = nullableEnum ["unified" "side-by-side"] "Initial diff layout.";
        softWrap = nullableBool "Soft-wrap long diff lines.";
        contextStep = nullableUnsigned "Number of context lines revealed per expansion.";
        theme = styleOptions [
          "added-line-bg"
          "removed-line-bg"
          "added-word"
          "removed-word"
          "gutter-added"
          "gutter-removed"
        ];
      };

      comments.initialState = nullableEnum ["draft" "todo"] "Initial state assigned to new comments.";
      keybindings = keybindingOptions;
    };

    settings = lib.mkOption {
      inherit (tomlFormat) type;
      default = {};
      example = lib.literalExpression ''
        {
          artifact.on_tui_quit = "write";
          keybindings.toggle-generated = ["h"];
        }
      '';
      description = ''
        Raw Gander TOML escape hatch. It recursively overrides both shared
        defaults and typed `dotfiles.gander.config` values; lists are replaced.
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = cfg.package != null;
          message = "dotfiles.gander.enable requires dotfiles.gander.package or an inputs.gander flake input.";
        }
      ];

      home.packages = lib.optional (cfg.package != null) cfg.package;
      xdg.configFile."gander/config.toml".source = tomlFormat.generate "gander-config.toml" mergedSettings;
      dotfiles.agentSkills = {
        gander-review.source = lib.mkDefault (
          if skillSourceDirectory == null
          then null
          else skillSourceDirectory + "/gander-review/SKILL.md"
        );
        gander-address-review.source = lib.mkDefault (
          if skillSourceDirectory == null
          then null
          else skillSourceDirectory + "/gander-address-review/SKILL.md"
        );
      };
    }
  ]);
}
