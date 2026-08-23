# Gander

[`gander`](https://git.sr.ht/~averagechris/gander) is a terminal UI and CLI for
reviewing `jj` changes, keeping durable comments and action items, building
walkthroughs, and exporting human or agent review artifacts. The pinned v0.8.1
package is exposed through the Gander flake input and installed by the Home
Manager module at `flakes/hm-modules/modules/gander.nix`. The module tracks the
v0.8 configuration schema.

## Enablement and package

The module is imported by the default dotfiles Home Manager module and is
enabled for `suremac`, `tater`, `thorny`, and `trap`:

```nix
dotfiles.gander.enable = true;
```

`dotfiles.gander.package` defaults to
`inputs.gander.packages.${system}.gander` (or the input's `default` package as a
compatibility fallback). Enabling the module adds that package to
`home.packages`, so both the TUI and the full `gander` CLI are available. Set the
option explicitly when evaluating the module without the Gander input.

The generated user configuration is
`$XDG_CONFIG_HOME/gander/config.toml`. Gander subsequently layers repository
`gander.toml`, deprecated `.gander/config.toml`, and an explicit `--config` file
over it. Prefer repository `gander.toml`; the `.gander` location is retained
upstream only for migration.

## Merge model and shared defaults

Configuration is assembled deterministically, from lowest to highest
precedence:

1. dotfiles shared defaults;
2. typed `dotfiles.gander.config` options;
3. raw `dotfiles.gander.settings`.

The merge is recursive for attribute sets. Scalars and lists are replaced, not
appended. The raw `settings` option uses Nixpkgs' TOML value type and is the
forward-compatibility escape hatch for a newer upstream field. Null typed values
are omitted, allowing Gander's own default to apply. Optional upstream values
such as `artifact.output_dir`, `agent.name`, and `identity.email` therefore use
`null` to mean "do not emit this typed value."

The shared layer enables soft wrapping, classifies standard lockfiles as
generated, creates new comments as actionable todos, and installs the complete
upstream Colemak Mod-DH override:

```toml
[comments]
initial-state = "todo"

[diff]
soft-wrap = true

[generated]
presets = ["lockfiles"]
```

Gander v0.8 no longer starts or owns agent processes. Agent harnesses should
drive it through its CLI, MCP, or ACP interfaces; `[agent]` now only configures
the identity name stamped on agent-authored annotations.

For example, typed values can be combined with a final raw override:

```nix
dotfiles.gander = {
  config = {
    diff = {
      view = "side-by-side";
      contextStep = 20;
    };
    artifact.onTuiQuit = "write";
  };

  # Raw TOML names are exact upstream names and win over typed values.
  settings.diff.context-step = 40;
};
```

## Typed configuration

Every current v0.8 upstream configuration field has a typed option under
`dotfiles.gander.config`. Nix option names use camel case where needed and the
renderer emits upstream's exact TOML spelling.

### Files, Jujutsu, generated files, and limits

| Typed option | Rendered TOML | Type |
| --- | --- | --- |
| `ignore.globs` | `ignore.globs` | list of strings |
| `jj.binary` | `jj.binary` | string |
| `generated.presets` | `generated.presets` | list of `lockfiles`, `api-clients`, or `vendored-assets` |
| `generated.globs` | `generated.globs` | list of strings |
| `limits.maxDiffLines` | `limits.max-diff-lines` | unsigned integer |
| `limits.nudgeDiffLines` | `limits.nudge-diff-lines` | unsigned integer; zero disables this nudge |
| `limits.nudgeFiles` | `limits.nudge-files` | unsigned integer; zero disables this nudge |

Gander combines generated presets and custom generated globs. Generated files
remain reviewable and are also detected by upstream's first-ten-lines content
heuristic. Ignore globs instead remove matching files from the visible diff.
For a deterministic Jujutsu executable, set `config.jj.binary` to an absolute
`lib.getExe pkgs.jujutsu`-derived path; the package is named `jujutsu`, not `jj`.

### Artifacts

| Typed option | Rendered TOML | Allowed values |
| --- | --- | --- |
| `artifact.format` | `artifact.format` | `json`, `markdown`, `html` |
| `artifact.profile` | `artifact.profile` | `human`, `agent`, `team` |
| `artifact.outputDir` | `artifact.output_dir` | string |
| `artifact.basename` | `artifact.basename` | string |
| `artifact.onTuiQuit` | `artifact.on_tui_quit` | `never`, `write`, `stdout` |

The underscores on `output_dir` and `on_tui_quit` are intentional upstream
schema exceptions. Relative output directories are resolved against the
reviewed repository. `onTuiQuit = "write"` requires either an output directory
or the corresponding TUI CLI output option.

### Syntax highlighting

`syntax.enabled` is a boolean, `syntax.languages` is a list of built-in language
names, and `syntax.mappings` is a list of typed records:

```nix
dotfiles.gander.config.syntax = {
  enabled = true;
  languages = ["nix" "rust" "toml"];
  mappings = [{
    name = "nix";
    extensions = ["nix.in"];
    filenames = ["flake-template"];
  }];
};
```

Each mapping has required `name` and default-empty `extensions` and `filenames`
lists. Mappings only add detection for a built-in language that is also enabled
in `languages`; they do not load external grammars. The typed
`syntax.theme.<name>` string fields are:

`attribute`, `comment`, `constant`, `function`, `keyword`, `number`, `operator`,
`property`, `punctuation`, `string`, `type`, and `variable`.

Styles accept Gander's named, indexed, or `#rrggbb` colors, modifiers such as
`bold` and `underline`, and `on <color>` backgrounds.

### Identity, comments, theme, UI, and diff display

| Typed option | Type or values |
| --- | --- |
| `agent.name` | nullable agent annotation identity |
| `identity.name` | nullable local human annotation identity |
| `identity.email` | nullable email used for Jujutsu author matching |
| `comments.initialState` | `draft` or `todo` |
| `comments.defaultChannel` | nullable `onboarding`, `delegation`, `collaboration`, or `note` |
| `theme.mode` | `auto`, `dark`, or `light` |
| `theme.transparent` | boolean |
| `ui.filePaneAutoHideWidth` | unsigned integer |
| `ui.filePaneSplitPercent` | unsigned integer |
| `ui.menuBar` | boolean |
| `diff.wordHighlight` | boolean |
| `diff.lineBackground` | boolean |
| `diff.gutterBar` | boolean |
| `diff.view` | `unified` or `side-by-side` |
| `diff.softWrap` | boolean |
| `diff.contextStep` | unsigned integer |

The typed diff theme strings are `added-line-bg`, `removed-line-bg`,
`added-word`, `removed-word`, `gutter-added`, and `gutter-removed`. Theme option
names already match TOML and therefore remain hyphenated in Nix.

`draft` comments are private reviewer state; `todo` comments are ready and
actionable. `resolved` is durable history but is intentionally not a valid
initial state.

### Complete keybinding map

Every `config.keybindings.<action>` option is a nullable list of strings. A
non-null list replaces the upstream list for that action, and `[]` removes its
configurable bindings. Gander retains immutable movement/select/close safety
fallbacks and rejects bindings that collide in an overlapping UI context.

Set `config.keybindings.preset` to `gander` or `hunk`. The complete v0.8 typed
action set also supports per-action overrides:

- global and target: `quit`, `help`, `yank-handoff`,
  `move-down`, `move-up`, `toggle-focus`, `diff-top`, `diff-bottom`,
  `compare-trunk`, `compare-parent`, `target-chooser`, `revset-input`,
  `stack-next`, `stack-previous`, `operation-picker`, and `jj-helpers`;
- navigation: `next-unviewed`, `previous-unviewed`, `next-comment`,
  `previous-comment`, `file-search`, `symbol-outline`, `next-symbol`,
  `previous-symbol`, `next-changed-hunk`, `previous-changed-hunk`, `next-file`,
  `previous-file`, `attention-promote`, `attention-demote`, `attention-focus`,
  `attention-glance`, `glance-peek`, `glance-acknowledge`,
  `glance-acknowledge-all`, `spotlight-next`, `spotlight-previous`, and
  `advance-review`;
- review and display: `toggle-large-diff`, `toggle-agent-order`, `flag-list`,
  `open-work`, `activity`, `walkthrough-list`, `draft-list`,
  `scroll-down`, `scroll-up`, `scroll-diff-left`, `scroll-diff-right`,
  `mark-viewed`, `toggle-viewed`, `mark-all-viewed`, `toggle-generated`,
  `cycle-viewed-filter`, `toggle-fold`, `collapse-fold`, `expand-fold`,
  `toggle-context-fold`, `expand-context`, `expand-context-all`,
  `collapse-context`, `view-options`, `toggle-word-highlight`,
  `toggle-line-background`, `toggle-gutter-bar`, `toggle-diff-wrap`,
  `toggle-annotation-artifacts`, `toggle-file-pane`, `toggle-diff-view`,
  `widen-file-pane`, `narrow-file-pane`, `range-comment`, `mark-walkthrough`,
  and `cancel-range-comment`;
- comments and editor: `comment`, `cycle-comment-state`, `edit-comment`,
  `delete-comment`, `comment-list`, `comment-list-new-general`,
  `comment-list-ready`, `comment-list-cycle-action`,
  `comment-list-cycle-kind`, `submit-comment`, `cancel-comment`,
  `insert-newline`, `delete-char`, and `cycle-comment-channel`;
- picker and popup: `target-picker-down`, `target-picker-up`,
  `popup-move-down`, `popup-move-up`, `popup-select`, `popup-toggle`,
  `popup-close`, `popup-close-q`, `draft-accept`, `draft-edit`,
  `draft-discard`, `walkthrough-delete`, `walkthrough-move-down`, and
  `walkthrough-move-up`;
Gander accepts the legacy raw alias `task-list` for `open-work`; use the
canonical typed name above.

## Colemak Mod-DH bindings

The shared preset exactly matches upstream's documented, regression-tested
collision-free Colemak Mod-DH override:

| Action | Keys |
| --- | --- |
| `move-down` | `n`, Down |
| `move-up` | `e`, Up |
| `next-unviewed` | Alt-J |
| `previous-unviewed` | Shift-J |
| `edit-comment` | Alt-E |
| `popup-move-down` | `n`, Down |
| `popup-move-up` | `e`, Up |
| `comment-list-new-general` | Ctrl-N |
| `draft-edit` | Alt-E |

These changes are atomic. In particular, moving only normal navigation to
`n`/`e` would collide with unmodified popup, comment-center, draft, and zen
actions. Gander's immutable `j`/`k` and arrow safety aliases still work.

## Bundled agent skills

Gander embeds two skills in its package:

- `gander-review` authors a durable Gander review without changing code or
  posting to a forge;
- `gander-address-review` implements todo/action-item feedback and records the
  result in Gander state.

The module registers both skill sources from the pinned package with the shared
`dotfiles.agentSkills` renderer. Skill content therefore follows the selected
package without running a mutable installer during activation. Both skills are
enabled by default when all of the following are true:

- `dotfiles.gander.enable` is true;
- `programs.opencode.enable` is true;
- `dotfiles.gander.package` is non-null.

Use the standardized per-skill controls to disable or customize either skill:

```nix
dotfiles.agentSkills.gander-review.enable = false;
dotfiles.agentSkills.gander-address-review.extraText = ''
  ## Host workflow

  Confirm the local review state before editing.
'';
```

`patches` is also available when local behavior must replace upstream text. See
[`docs/opencode.md`](/docs/opencode.md) for the common renderer contract.

OpenCode reads configuration and skills at process startup. Restart a running
OpenCode session after activation to load newly linked or updated skills.

## v0.8 workflow notes

Comments are the primary feedback unit. `draft` is private reviewer state,
`todo` requests implementation, and `resolved` retains history. Optional action
items coordinate groups of comments or external work; closing an action item
does not implicitly resolve linked comments. Walkthroughs provide an ordered
reading path, and `gander handoff --mode delegate` exports selectors,
objectives, constraints, acceptance criteria, and verification guidance for an
implementing agent.

Review state belongs under `$XDG_STATE_HOME/gander`, not in the repository.
`--state-file` changes storage selection but does not select the code workspace.
The `gander skills list/show/install` commands run without repository or `jj`
initialization.

## Verification and updates

The Home Manager flake has a focused `gander-module-config-and-skills` check. It
evaluates the module, renders representative values from every configuration
section (including exact hyphen/underscore spelling and raw precedence), checks
the selected skill's declarative source, verifies per-skill disablement, and
ensures no activation-time installer remains.

```sh
nix build ./flakes/hm-modules#checks.$(nix eval --raw --impure --expr builtins.currentSystem).gander-module-config-and-skills
nix flake check ./flakes/hm-modules --no-build
jj lint
```

Gander is a flake input. Version bumps should update every relevant root, Home
Manager, and enabled-host lockfile node together so evaluation paths do not
remain split across releases.
