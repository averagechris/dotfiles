# OpenCode

This repository manages OpenCode through the Home Manager module at
`flakes/hm-modules/modules/opencode/`.

OpenCode itself comes from the upstream `github:anomalyco/opencode/v2` flake
input, not from nixpkgs. The current pin reports version `2.0.3`; the exact
revision and package lifecycle live in [OpenCode patch lifecycle](opencode-patches.md).
The upstream flake builds its `packages/cli` package. `flakes/base-lib/` exposes
that package through the shared overlay as `pkgs.opencode`, and
`flakes/hm-modules/` mirrors the same overlay for standalone module evaluation
checks. All fourteen lock graphs carry the same OpenCode revision.

This keeps OpenCode close to upstream releases while preserving the normal
`pkgs.opencode` and Home Manager `programs.opencode.package` integration points.

## What it configures

- custom primary and sub-agents
- the `oconf` helper and shell function for interactive or direct model trials via `OPENCODE_CONFIG_CONTENT`
- repo-managed skills deployed into `~/.config/opencode/skills/`
- repo-managed slash commands deployed globally into `~/.config/opencode/commands/`, including `/what` for concise, jargon-free restatements
- MCP server definitions written into the generated OpenCode config
- optional `OPENROUTER_API_KEY` shell export via `dotfiles.opencode.openrouterApiKeyFile`
- optional `CIRCLECI_TOKEN` shell export via `dotfiles.opencode.circleciTokenFile`
- agent-specific runtime packages and prompt metadata exposed via `dotfiles.opencode.agentTools`
- host-specific private skill appendices materialized during Home Manager activation
- host-specific named references to relevant local repositories
- on `suremac`, client-owned CLI preferences with attention desktop notifications
  enabled and notification sound disabled
- on hosts with `dotfiles.devCache`, an automatically loaded
  `shell.create.before` plugin hook sets `CARGO_INCREMENTAL=0` for each
  OpenCode shell invocation so parallel isolated Rust workspaces favor the
  shared sccache without changing interactive shells
- on hosts with direnv enabled, a `dotfiles-direnv` plugin uses the same
  per-invocation hook, including the invocation's cwd and mutable environment,
  to load each working directory's direnv-allowed dev shell environment
- local automatic compaction at 350,000 input tokens for the primary aliases
  and pinned subagent models, with warming explicitly disabled

## Long-session compaction

The managed V2 configuration keeps local automatic compaction enabled, retains
15,000 recent tokens, and uses the default 20,000-token buffer. For the current
primary aliases and pinned OpenRouter agent models it overrides only the catalog
`limit.input` value to 370,000 and selects `compaction.mode = "local"`. It does
not enable provider-native compaction or replace catalog IDs, capabilities, or
truthful context/output limits.

V2's automatic threshold is
`min(input limit - buffer, context limit - max(output reserve, buffer))`.
With the observed catalog limits (922k input, roughly 1.0–1.05m context, and
128k output), the 370k input policy makes that threshold exactly 350k; a session
ending around 230k remains below it. Paid testing confirmed local compaction
works while OpenRouter provider-native compaction is unsupported. Source,
evaluation, and credential-free runtime checks assert this policy.

## Local repository references on suremac

`suremac` configures OpenCode V2 references for three checkout indexes and a
small set of frequently useful Surecraft repositories. The index aliases are
`sure-workspace` for `~/sureapp`, `personal-projects` for `~/projects`, and
`oss-contrib` for `~/contrib`. Their descriptions direct agents to canonical
direct-child checkouts; managed task clones under `~/sureapp/ws` and
`~/projects/ws` are not canonical sources.

The focused Surecraft references cover `surecraft-core`,
`product-configuration`, `rating-calculator`, `orchestrasure`,
`surecraft-apps`, `surecraft-api-docs`, and `surecraft-e2e-tests`. Each alias
maps to one local directory and describes that repository's role. Attachments
list only the referenced root's immediate entries, so agents must inspect a
specific child path for deeper context. These company paths stay in the
`suremac` host configuration rather than the shared OpenCode settings.

## V2 trial and migration

The Nix package and generated configuration are immutable. Do not install a
second OpenCode with `curl` or `npm` while trying V2, because it can collide
with the Nix-managed package. On Darwin, run the host's `nh darwin build`
first, then switch only when you are ready to activate the result.

Before the first V2 use, stop relevant OpenCode servers, then separately copy
the data directory (`~/.local/share/opencode`, including its SQLite database and
WAL files) and readable configuration (`~/.config/opencode`) to a backup. Stop
servers before any filesystem copy so SQLite and its WAL stay consistent. Do
not roll back to V1 after V2 has migrated the data unless you first stop the
servers and restore the data backup; restore configuration separately if
needed. V2 owns migration of global writable CLI preferences.

As an optional read-only preflight, inspect the copied V1 database (with its WAL
beside it), never the live database:

```sh
sqlite3 -readonly "$HOME/.local/share/opencode-v1-backup/opencode.db" \
  'SELECT count(*) AS completed_migrations FROM "migration";'
```

For the pinned 1.18.29 V1 state, expect at least 38 completed migrations before
proceeding. Replace the example path with the database in your backup, not the
live `~/.local/share/opencode` path.

The pinned Home Manager release does not expose a V2 `cli.json` option. On
`suremac`, activation recursively and atomically merges the selected existing
preferences with attention desktop notifications enabled and notification sound
disabled into the client-owned `~/.config/opencode/cli.json`. Unrelated TUI
settings survive. If the existing JSON is malformed, activation fails rather
than clobbering it.

After activation, exit and restart any shared OpenCode server before using the
new package. A server that survived activation can continue serving the old
code or configuration to new clients.

## Session cleanup on suremac

`dotfiles.opencode.sessionCleanup` installs `opencode-session-cleanup` and a
macOS user launchd agent on `suremac`. The agent checks at the top of every hour
on weekdays, but uses a date stamp so it performs deletion at most once per
calendar day. It defers when the one-minute CPU load is at or above 60% of
logical CPU capacity, or when `ctx` is reading session storage; launchd tries
again at the next hourly check.

The V2 cleanup first checks the managed service with the read-only
`opencode service status` discovery command. If the service is stopped or its
status cannot be read, cleanup defers without starting one. It then checks
active sessions through the running managed OpenCode service. An
active session defers cleanup, while an OpenCode process by itself does not,
because the V2 background service normally remains running. Session listing
also goes through that service, and deletion uses OpenCode's supported
`opencode session delete` command, so selection and mutation use the same
service state.

The selector considers sessions whose `time_updated` is more than 45 days old
and protects at least the 25 newest sessions, including when every session is
older than the retention window. Deletion cascades to child sessions, so it
selects only maximal subtrees in which every session is eligible and outside the
protected newest set. The cleanup follows every cursor page, then rechecks
activity and recomputes the safe subtrees before each delete. A session can still
change in the small interval between the final check and the delete, so this is
not an atomic guarantee. Failed deletions do not advance the daily stamp,
allowing a later check to retry.

The launchd log is `~/Library/Logs/opencode-session-cleanup.log`; the daily
stamp is `~/.local/state/opencode-session-cleanup/last-run`. launchd does not
wake a sleeping Mac, so the next hourly opportunity after wake performs the
check.

## Trying out models with `oconf`

The module installs an `oconf` helper for trialing new models without
touching any persistent configuration. It emits shell exports that set the
`OPENCODE_CONFIG_CONTENT` environment variable, which OpenCode merges last
when its server starts. Use `opencode --standalone` for trials. A V2 client
connected to an existing background server does not replace that server's
configuration with the client's environment. Do not restart a shared server
just to try a model.

A matching `oconf` shell function (installed for zsh and bash) evals the
helper's output in the current shell:

```zsh
# Interactive picker: choose a session/general model plus optional per-agent
# overrides, then launch.
oconf && opencode --standalone

# Direct: trial a model for every role (session model plus every agent that
# has a pinned model in the deployed config).
oconf openrouter/x-ai/grok-4.5 && opencode --standalone

# Keep the normal orchestrator model, trial a coding model on specific agents.
oconf openrouter/x-ai/grok-code minion build && opencode --standalone

# Optionally set a reasoning variant on the targeted agents.
oconf -v high openrouter/some-new-model && opencode --standalone

# Clear overrides for the current shell.
oconf -u
```

The interactive flow collects intent in two quick picks, then hands you the
whole plan for review:

1. **Trial model** — fuzzy-search over live `opencode models` output. `Esc`
   skips, leaving the session model unchanged.
2. **Scope** — one choice: all roles (session model plus every pinned agent),
   session only, or pick specific agents (TAB multi-select).
3. **Plan review** — the tool drafts a plan file and opens `$EDITOR` (like a
   commit-message editor). One line per override; tweak any model, add or
   delete agents, set variants:

   ```
   *       = openrouter/x-ai/grok-4.5
   minion  = openrouter/x-ai/grok-code variant=low
   ```

   Save and quit to apply; quit with an empty plan to cancel. Every model is
   validated against live `opencode models` output before applying. The plan
   header also lists notable models — newest on OpenRouter and free-tier
   options, filtered to models this opencode can access — sourced from the
   OpenRouter catalog, cached for a day under `~/.cache/oconf/`, and silently
   omitted when offline.

Direct mode stays non-interactive for scripted use:

```zsh
# Trial a model for every role (session model plus every agent that has a
# pinned model in the deployed config).
oconf openrouter/x-ai/grok-4.5 && opencode --standalone

# Keep the normal orchestrator model, trial a coding model on specific agents.
oconf openrouter/x-ai/grok-code minion build && opencode --standalone

# Optionally set a reasoning variant on the targeted agents.
oconf -v high openrouter/some-new-model && opencode --standalone

# Clear overrides for the current shell.
oconf -u
```

In both modes the helper prints exactly what it overrode before emitting the
exports, so an in-progress trial is always visible. Overrides persist in the
shell until `oconf -u`. Agent discovery reads `$OPENCODE_CONFIG_DIR` (default
`~/.config/opencode`), so tests can point it at a fixture directory. For
scripted plan use, set `OCONF_PLAN_FILE` to a file of
`<agent> = <model> [variant=<v>]` lines to skip the pickers and editor.

V2 can return an empty model list while a new location activates its plugins.
The helper makes up to five calls when responses are empty, with 250 ms
between calls. CLI failures are not retried. If the list remains empty, wait for
the server to finish loading and check `opencode models` before retrying.

### Verifying the V2 integration without activation

Run the opt-in runtime check with the built binary and the emitted Home Manager
`opencode` directory, containing `opencode.json`, agents, skills, commands, and
both local plugins:

```sh
python3 flakes/hm-modules/modules/opencode/tests/runtime-v2.py \
  /nix/store/<built-package>/bin/opencode \
  /nix/store/<emitted-artifacts>/opencode
```

The check requires Bash, jq, and direnv on `PATH`, and disabled MCP servers in
the emitted config. It creates an isolated HOME and XDG tree under `TMPDIR`,
starts authenticated localhost servers on a temporary port, and stops them on
exit. It retains request/response records and process logs at the printed path.
It uses a local provider catalog fixture, makes no model completion calls, and
does not read live credentials or activate Home Manager.

The check waits until both repo-managed plugins report an active state, then
covers generated resource discovery, normalized permissions and
Minion's subagent resource policy, effective shell cwd, real direnv allow/block
behavior, the Rust environment override, cold `oconf` enumeration, and config
overrides on a fresh server. It checks the configured depth limit, not actual
model-driven nested delegation. Raw `shell.create` exercises shell hooks but
does not run the shell tool's permission scanner; permission evaluation is
tested separately through the session permission API.

The normal module checks also run source-level plugin and cleanup contracts. The
session cleanup test gains a real-runtime portion only when `OPENCODE_V2_BIN`
points at a built binary. These checks use fixtures for model catalogs and
session ages, but they do not replace OpenCode or direnv with mocks. They do not
make a paid model request, so provider authentication and model completion stay
outside this migration's automated coverage.

For manual API checks, V2 initializes location plugins asynchronously. An empty
first `agent.list`, `skill.list`, `command.list`, or `plugin.list` response is
not proof of missing config. Keep the server alive and wait for activation.
Use `location[directory]` or `x-opencode-directory`, and canonicalize macOS
paths so `/var` and `/private/var` do not initialize separate locations. The
pinned Nix package uses channel `prod`, so its managed service configuration is
`service-prod.json`, not `service.json`. An explicit `--server` client needs the
matching `OPENCODE_PASSWORD`; setting that variable does not change the password
of an existing managed service.

## Repo-managed slash commands

The pinned Home Manager OpenCode module supports `programs.opencode.commands`
with command names mapped to inline text or Markdown files. This module maps
the repo-managed `commands/what.md` to the global `/what` command. It asks
OpenCode to restate its last message plainly and concisely, and to use the
`impactful-writing` skill if needed.

## Declarative CLI skills

CLI modules register bundled skills in the shared `dotfiles.agentSkills`
registry. Every registered skill is enabled by default and Home Manager links
the rendered result at `~/.config/opencode/skills/<name>/SKILL.md` when OpenCode
is enabled. Hosts can customize each skill independently:

```nix
dotfiles.agentSkills.rdny-browser = {
  enable = true;
  patches = [./rdny-browser.patch];
  extraText = ''
    ## Host workflow

    Use the host browser wrapper for visible sessions.
  '';
};

dotfiles.agentSkills.gander-address-review.enable = false;
```

The upstream `source` may be either one `SKILL.md` file or a complete skill
directory containing `SKILL.md`. Complete directories are copied recursively,
so Agent Skills companion content such as `assets/` and `references/` remains
available beside the instructions. The renderer applies `patches` in order with
zero fuzz specifically to `SKILL.md`, then appends `extraText` to `SKILL.md`;
companion files are left unchanged. A directory source without `SKILL.md` fails
evaluation or rendering clearly. File sources retain the existing one-file skill-directory
behavior and are not expanded to their parent directory, since flat Markdown
bundles can share one parent. Use a patch when changing or removing upstream
instructions; its build failure intentionally detects upstream drift. Use
`extraText` only for additive local guidance. CLI modules own source
registration, while hosts normally set only `enable`, `patches`, or `extraText`.

Sideshow uses both source forms for distinct skills: `sideshow-deck-author`
comes from the selected upstream package source as a complete directory, so all
of its companion files are deployed recursively, while `sideshow-work-story`
remains a local repo-managed evidence and narrative skill. Work-story hands a
bounded evidence/story packet to deck-author when an actual deck is requested;
deck-author exclusively owns deck creation, revision, project-artifact mechanics,
checks, builds, review, and publishing. A Sideshow package override without a `src`
attribute installs normally but does not register or audit the upstream skill.

New CLI modules should import `agent-skills.nix` and register every bundled skill
with a default source; they should not add bespoke skill options or activation
scripts:

```nix
{
  config,
  lib,
  ...
}: let
  cfg = config.dotfiles.exampleCli;
  skillSourceDirectory =
    if cfg.package != null && cfg.package ? src
    then cfg.package.src + "/skills"
    else null;
in {
  imports = [./agent-skills.nix];

  config = lib.mkIf cfg.enable {
    dotfiles.agentSkills.example.source = lib.mkDefault (
      if skillSourceDirectory == null
      then null
      else skillSourceDirectory + "/example/SKILL.md"
    );
    dotfiles.agentSkillBundles.example-cli = {
      sourceDirectory = lib.mkDefault skillSourceDirectory;
      expectedNames = ["example"];
    };
  };
}
```

Use one registry entry per skill rather than a names allowlist. This makes every
new skill available by default while preserving stable host overrides such as
`dotfiles.agentSkills.example.enable = false`.

Every package-backed registration must also declare an audited
`dotfiles.agentSkillBundles` manifest. The default `directories` layout discovers
`<name>/SKILL.md`; `layout = "flat-markdown"` discovers `<name>.md`. Evaluation
fails when discovered and expected names differ, reporting additions and
removals separately. Package upgrades therefore cannot silently expose or omit a
skill: review the changed upstream skill set, update `expectedNames`, ensure each
name has a registry entry, then keep its default enablement, patch it, or disable
it explicitly.

On Linux, the module wraps the OpenCode package with `LD_LIBRARY_PATH` pointing
at `stdenv.cc.cc.lib`. This lets OpenCode's native file-watcher binding find
`libstdc++.so.6` on NixOS. Without the wrapper, OpenCode may log or surface
startup failures while loading project or global files, including custom tools.

## Agent-exposed tools

The OpenCode module installs a small, explicit set of agent-specific tools and
generates the system-prompt tool note from the configured list when
`programs.opencode.enable = true`. Hosts that leave OpenCode disabled do not get
the agent runtime tools or generated OpenCode config files in their Home Manager
profile.

The `orchestrator` is the generated OpenCode default agent, making decomposition
and Minion-first routing the normal entry point. It uses the same open-by-default
shell safety posture as Build, is tuned for ambitious projects, and can delegate
work across five coding tiers: `tiny`, `luna`, `minion`,
`build`, and `wise`. Tiny uses GPT-5.6 Luna at `low` for mechanical work, while
the distinct Luna tier uses the same model at `high` for bounded work requiring
more reasoning. Minion uses GPT-5.6 Sol at `low` and is the default implementation
tier: the orchestrator decomposes work and supplies clear implementation packets
so Minion performs the bulk of coding. Build is reserved for ambiguity, breadth,
investigation, or coordination that planning cannot reasonably remove. The
higher-capability `wise` agent uses `openrouter/anthropic/claude-fable-5.1#high`.
All coding agents share one generated shell permission
policy so safety-rule changes stay consistent across tiers. Their concise
descriptions summarize the intended delegation tradeoff so primary agents can
choose effectively from the subagent tool.
Wise also carries a stable judgment stance for high-consequence work: keep
decisions falsifiable, treat implementation as design evidence, and make
disagreement explicit.

The repo-managed `test-curation` skill is conditional. When the orchestrator
delegates review of a code change that added or materially changed tests, it tells
that reviewer to load the skill. The orchestrator does not load it itself. The
reviewer decides which changed tests deserve permanent retention; an implementation
handoff may then remove low-value tests and run focused checks. Non-code work and
changes without test changes do not carry this guidance.

V2 stores the delegation limit at `experimental.subagent_depth = 2`.
Upstream counts a direct subagent at depth one, so this permits one nested
handoff while still preventing longer delegation chains. The orchestrator
policy requires every handoff prompt to say whether sub-delegation is
appropriate rather than adding situational guidance to all delegated-agent
prompts. Handoffs normally tell agents to complete their packets directly; they
may explicitly allow a sparse, separable handoff when it is useful. Build may
re-delegate sparingly when unresolved complexity warrants it. Minion is more
tightly scoped: its delegation permissions allow only Explore for focused
research and Tiny for mechanical support, not coding agents for implementation
or build work. Handoff prompts steer justified nested work through the
subagent tool and say not to use `opencode run` as a routine delegation escape
hatch. That command remains permission-allowed rather than banned.

The managed agent catalog emits OpenCode V2-native frontmatter: model variants
use the `model#variant` form, request tuning lives under `request.body`, and
ordered `permissions` rules use the `shell` and `subagent` action names.

The repo-managed `subagent-selection` skill and orchestrator both render the
canonical routing policy from `agent-selection-policy.md` and the relative
intelligence, taste, speed, and cost scorecard from
`agent-selection-table.md`. The policy defines tier boundaries, residual
uncertainty handoffs, escalation, review limits, and finding severity gates;
update those shared sources rather than restating the rules in consumers or
documentation. The scorecard describes relative qualities rather than a utility
ranking: routing favors the least expensive tier likely to succeed once it meets
the task's capability threshold. Its canonical rubric defines capability bands,
intrinsic response speed at comparable work, and nonlinear intrinsic model-cost
bands independently of the tasks each tier is assigned.

The local `architect` skill handles explicit design requests and costly-to-reverse
contracts, data models, ownership boundaries, state models, extension points, and
multi-system migrations. It grounds existing systems with `how`, produces a
compact design packet, and returns implementation guidance to its caller when
requested. `how` remains the route for explaining or critiquing existing
architecture. It explores and synthesizes directly by default, using focused
Explore agents only when breadth or uncertainty warrants the cost. `why` starts
with code, repository docs, VCS history, and linked records. It searches other
evidence sources or delegates investigation only when a lead or unresolved
rationale makes that work useful. `code-review` and opt-in `interrogate-me`
review implemented work.

The repo-managed `project-map` skill is for efforts whose decisions cannot fit in
one agent session. It keeps a durable, Wayfinder-compatible map plus child
decision files. The map indexes resolved decisions and records unresolved fog;
each child owns its question and answer. It creates children only for precise
questions and supports Wayfinder's `research`, `prototype`, `grilling`, and
`task` metadata through existing local capabilities rather than companion
skills. Short-lived decisions are revised in place unless their old answer has
created lasting external obligations.

Project-map decisions may link supporting visual explanations, prototypes,
demos, reviews, and verification results when prose alone makes structure,
behavior, alternatives, or delivered behavior hard to judge. Each artifact
names the question or claim it evaluates and links back to the relevant decision
or canonical map. It remains a projection or evidence, not another authority;
accepted review feedback is reconciled into the map or child decision. Verified
results identify the exact implementation revision or delivered state and link
the underlying checks without replacing automated checks or delivery records.
External delivery items may link useful artifacts according to project
conventions, but neither attachments nor one artifact per item are required.

Project maps describe discovery, not delivery tracking. Linear or SourceHut
holds organization-visible implementation work, ownership, progress, delivery
dependencies, change links, and compliance evidence. The relationship is
many-to-many: agents must not create one tracker issue per map item or copy map
blockers into tracker dependencies by default. Delivery issues need a concrete
outcome and normally one coherent, reviewable change or PR. They link to the
canonical map and relevant named decisions. Cross-repository efforts use one
canonical map linked from each repository and tracker initiative when the user
explicitly asks or approves those backlinks. Synthesis may use `architect` and
`technical-writing`, then the repository's tracker skill, but ordinary delivery
issue creation and production implementation do not become allowed merely to
establish backlinks. Production implementation starts only after an explicit
human transition out of discovery, and the map alone never authorizes external
mutation.

Implementation packets require proof at the boundary where behavior is claimed.
Agents escalate when implementation disproves a design assumption, favor
subtraction unless added scope has a clear payoff, and use fresh scoped handoffs
when work or context no longer fits the packet.

The built-in `explore` subagent keeps its upstream prompt and tools but is
configured through `settings.agents.explore` to use
`openrouter/openai/gpt-5.6-luna#medium`. This favors cheap,
parallel codebase research with a research-specific prompt and tool set; Tiny
remains narrower and mechanical, while Luna handles bounded reasoned work.

OpenCode normally prompts before any tool touches a path outside the project it
was started in. To keep delegated coding work smooth without opening up entire
project trees, the Home Manager module derives
ordered `permissions` rules for the `external_directory` action from
`dotfiles.jujutsu.workspaces.projectGroups`: each canonical managed workspace
namespace (`<project-group>/<workspace-dir>/**`, such as `~/projects/ws/**` and
on `suremac` also `~/sureapp/ws/**`) is trusted by default. This covers files
created by `jj ws add` while preserving prompts for unrelated external
directories.

The same external-directory policy allows read/search access to package sources
and build outputs under `/nix/store`, general temporary files under `/tmp` and
`/private/tmp`, plus OpenCode's session-specific directories under
`/var/folders/**/T/opencode` and `/private/var/folders/**/T/opencode`. The Nix
store is immutable to normal users, so allowing the external path lets agents
use OpenCode reads and searches or commands such as `rg` there without granting
them a practical write path. Both temporary-path spellings are present because
macOS canonicalizes `/tmp` and `/var` through `/private`; unrelated external
directories continue to prompt.

For Build, `orchestrator`, `minion`, `luna`, `tiny`, and `wise`, shell execution
never asks for approval. Their shared policy starts with `"*": "allow"`; later
rules only hard-deny commands that must not run. Direct reads of encrypted secret
material with common text/search commands, privilege escalation (`sudo`, `doas`,
`su`), and `mkfs*` remain denied. The separate read-only Plan agent policy is
unchanged.

Everything else inherits the catch-all allow, including `.env`/agenix/sops
workflows, SSH and remote copies, deploys and switches, ownership and mode
changes, `diskutil`/`dd`, process and service control, Git/jj/GitHub operations,
and kubectl reads or mutations. This intentionally favors uninterrupted coding
agent execution over approval prompts.

Catastrophic recursive deletion is denied rather than prompted. The generated
simple-glob rules cover `rm -rf`, `rm -fr`, and `rm -r` forms targeting `/`, the
current or parent directory, `~`, `$HOME`, `/Users/chris`, or `/home/chris`, plus
straightforward trailing-slash, descendant, and later-operand variants. Normal
absolute cleanup such as `/tmp/cache` remains allowed; there is deliberately no
blanket block on absolute deletion.

These rules are guardrails, not an argument-aware shell sandbox. OpenCode's
permission wildcards only support simple anchored `*` and `?` matching, so they
cannot prove behavior involving quoting, expansions, command substitution,
unusual option placement, symlinks, or every possible multi-operand spelling.
In particular, a pattern that tried to recognize the literal shell source `/*`
would also match every absolute path, so the policy does not add that broad deny.

The old repeated prompts came from last-match-wins evaluation: narrower `ask`
rules after the catch-all allow overrode it. OpenCode also scans compound shell
commands component by component, so one asked component in an `&&` or `;`
operation asked for the whole operation. Removing every coding-agent shell
`ask` rule eliminates both prompt paths.

Host-exposed browser automation follows the open default: `rdny` commands are
allowed for Build agents unless they hit a later risky pattern.

Host-specific investigation CLIs such as `pup`, `sentry`, and `kubectl` follow
the same open coding-agent default.

When adding command allow rules, prefer an exact command plus a command-space
wildcard, for example `tool` and `tool *`. Avoid bare prefix allow patterns such
as `tool*`, because they also match unrelated executable names like
`tool_malicious`. Conservative `ask`/`deny` override rules can be broader when
the intent is to interrupt anything in that command family.

### Env-prefixed runner commands

OpenCode V2's legacy shell scanner evaluates shell permission rules against the
command source it extracts from the shell AST. For inline environment
assignments, that source can include the assignments, so a command such as:

```bash
SERVICE_REDIS_PORT=51820 SERVICE_POSTGRES_PORT=51821 just test ...
```

does not match the existing `"just *": "allow"` rule. The prompt may still offer
an "always" approval for `just *`, but that session approval does not cover the
next env-prefixed invocation because the evaluated pattern still starts with the
assignment prefix.

This module patches `pkgs.opencode`, which is supplied by the upstream OpenCode
flake overlay, with module-local patches under
`flakes/hm-modules/modules/opencode/patches/`.

The v1 nested-prompt, Bun, and old-Drizzle patches are retired in V2. See
[OpenCode patch lifecycle](opencode-patches.md) for the active patch inventory,
validation workflow, and removal criteria.

`opencode-strip-env-assignments.patch` normalizes shell permission patterns by
stripping safe leading inline environment assignments before permission
matching. With the example above, OpenCode authorizes `just test ...`, so the
existing `just` and `just *` allow rules work across projects no matter what
service-specific environment prefix they use.

The patch deliberately does not strip assignments containing command
substitution, such as `FOO=$(curl example.com) just test` or backticks. Those
assignments can execute code before `just` starts and therefore are not rewritten
for command-specific matching; the coding-agent catch-all still allows them.

The upstream V2 flake builds a fixed-output `opencode-node_modules`
derivation for `packages/cli`. Its install phase still recursively copies the
completed dependency tree, so the module retains a local override that copies
the source tree directly to `$out`, runs the inherited build, and removes
non-module files. A marker assertion makes upstream phase drift fail evaluation
instead of silently dropping changed build steps. Remove this temporary
workaround once upstream installs directly into the output, or an equivalent
replacement passes the output-equivalence check. See [OpenCode patch
lifecycle](opencode-patches.md) for the fixture and exact removal criterion.

Prefer this normalization patch over broad config patterns such as `*=* just *`.
OpenCode permission wildcards are anchored but simple (`*` and `?` only), so a
broad assignment-style pattern can accidentally match unrelated commands that
merely contain `=... just ...` in their arguments.

Agent-exposed tools and MCPs are configured separately:

- `dotfiles.opencode.agentTools` installs CLI tools into `home.packages` and
  mentions them in the primary agent runtime note.
- `dotfiles.opencode.agentSupportPackages` installs supporting packages into
  `home.packages` without mentioning them in the runtime note.
- `programs.opencode.settings.mcp` configures MCP servers in OpenCode itself;
  these are integrations the agent can use when enabled, but they are not part
  of the runtime-note tool list by default.

### Shared core packages

By default, all OpenCode-enabled hosts install:

- `jj` - Jujutsu VCS
- `nodejs` - JavaScript runtime
- `python3` - Python runtime
- `rg` - fast code search

These come from the module's built-in default tool list:

```nix
[
  { package = jujutsu; name = "jj"; description = "Jujutsu VCS"; }
  { package = nodejs; name = "nodejs"; description = "JavaScript runtime"; }
  { package = python3Minimal; name = "python3"; description = "Python runtime"; }
  { package = ripgrep; name = "rg"; description = "fast code search"; }
]
```

The Python entry intentionally uses the minimal interpreter package. It is enough
for ad hoc agent scripts and avoids retaining the full Darwin compiler/SDK
closure through the standard Python build on macOS. Use a project dev shell for
workflows that need extra Python packages or a specific interpreter version.

Each entry defines:

- the package to install in `home.packages`
- the tool name to mention in the primary agent prompts
- an optional extremely brief description when the name alone is not enough

Hosts append additional tools via `dotfiles.opencode.agentTools`, and the
module combines those with the built-in default tool list.

### Host-specific additions

Use `dotfiles.opencode.agentTools` for tools that should only be available to
agents on particular hosts. For example, `suremac` adds the AWS CLI, Ctx,
Kubernetes CLI, Datadog Pup CLI, Sentry CLI, GitHub CLI, rdny, Showboat,
Granola, Sideshow, and the Linear CLI. On Darwin, this host-specific list avoids
relying on unrelated system packages for agent workflows:

```nix
dotfiles.opencode.agentSupportPackages = [];

dotfiles.opencode.agentTools = with pkgs; [
  { package = awscli2; name = "aws"; description = "AWS CLI"; }
  {
    package = inputs.ctx.packages.${pkgs.stdenv.hostPlatform.system}.ctx;
    name = "ctx";
    description = "agent history search CLI";
  }
  { package = kubectl; name = "kubectl"; description = "Kubernetes CLI"; }
  { package = pup; name = "pup"; description = "Datadog CLI"; }
  { package = sentry; name = "sentry"; description = "Sentry CLI"; }
  { package = notion-cli; name = "ntn"; description = "Notion CLI"; }
  { package = gh; name = "gh"; description = "GitHub CLI"; }
  { package = showboat; name = "showboat"; description = "work documentation CLI"; }
  {
    package = inputs.linear-cli.packages.${pkgs.stdenv.hostPlatform.system}.linear;
    name = "linear";
    description = "Linear CLI";
  }
  {
    package = inputs.granola-cli.packages.${pkgs.stdenv.hostPlatform.system}.default;
    name = "granola";
    description = "Granola meeting notes CLI";
  }
  {
    package = inputs.sideshow.packages.${pkgs.stdenv.hostPlatform.system}.sideshow;
    name = "sideshow";
    description = "HTML slide deck CLI";
  }
];
```

Tool-specific modules can append their own entries too. `dotfiles.rdny` appends
`rdny` and registers the `rdny-browser` skill when enabled.

Primary agent prompts render a concise structured runtime note dynamically, for
example:

> Your runtime is a macOS environment. By default, your environment includes
> these additional tools: jj (Jujutsu VCS), nodejs (JavaScript runtime),
> python3 (Python runtime), rg (fast code search), aws (AWS CLI), ctx (agent
> history search CLI), kubectl (Kubernetes CLI), pup
> (Datadog CLI), sentry (Sentry CLI), ntn (Notion CLI), gh (GitHub CLI), showboat
> (work documentation CLI), linear (Linear CLI), granola (Granola meeting notes
> CLI), sideshow (HTML slide deck CLI), rdny (browser automation CLI). The
> project local dev shell may provide additional tooling.

The runtime note also appends a concise Nix usage rule telling agents to prefer
`nix build .#x` + `./result/bin/x` over repeated `nix run .#x` and to treat
`SQLite database is busy` as a harmless retry warning. This keeps parallel
agents from serializing on the nix store database; see
[suremac](/docs/suremac.md) for the daemon-side tuning.

Use `agentSupportPackages` for dependencies that a visible tool needs under the
hood but that the agent does not need to call directly.

## direnv environments for agent commands

`dotfiles.opencode.direnv.enable` (default: `programs.direnv.enable`) installs
the `dotfiles-direnv` OpenCode plugin at
`~/.config/opencode/plugins/dotfiles-direnv.js`. OpenCode V2 triggers the
`shell.create.before` plugin hook for every shell invocation in the server
process, with the
invocation's effective cwd and mutable environment. The plugin merges the
output of `direnv export json` for that directory into the command environment.

This means agents get project dev-shell tooling (via nix-direnv) transparently,
including subagents dispatched across repos with `workdir` outside the session
root. They should run project commands directly (`just test`, `cargo build`)
rather than wrapping them in `nix develop --command` or `direnv exec`; the
wrappers are slower and also defeat shell permission matching on the underlying
command. The runtime note tells agents this when the plugin is enabled.

Behavior details:

- The nearest `.envrc` is found by walking up from the command's cwd, stopping
  at the home directory. Only direnv-allowed files load; blocked or failing
  `.envrc`s are skipped silently and negative-cached for one minute, so a repo
  becomes available shortly after an interactive `direnv allow`.
- Results are cached per `.envrc` root with a five-minute TTL plus an mtime
  fingerprint over `.envrc`, `flake.nix`, `flake.lock`, and similar files.
  Warm nix-direnv evaluations take tens of milliseconds; the first load of a
  cold dev shell pays full flake evaluation (bounded by a ten-minute timeout),
  so warming big shells interactively first helps.
- If the OpenCode server was launched inside a direnv environment, commands running
  in directories without an `.envrc` receive the unload diff so the launch
  repo's dev shell does not leak into other projects.
- direnv reports unset variables as nulls; the hook can only merge over the
  OpenCode server process environment, so those become empty strings.

The plugin substitutes the host's `programs.direnv.package` binary path at
build time and shares the user's direnv allow database and nix-direnv cache
with interactive shells.

## MCP integrations

All MCP servers are defined under `mcp.servers` in
`flakes/hm-modules/modules/opencode/settings.nix` and default to
`disabled = true` unless explicitly turned on.

| MCP server | Type | Default | Notes |
|------------|------|---------|-------|
| `context7` | remote | disabled | Documentation lookup |
| `circleci` | local | disabled | Launches `@circleci/mcp-server-circleci` via the module's Node-aware `npx` wrapper; requires `CIRCLECI_TOKEN` when enabled |
| `datadog` | remote | disabled | Datadog MCP endpoint |
| `gh-grep` | remote | disabled | GitHub code search via Grep |
| `github` | remote | disabled | GitHub Copilot MCP endpoint |
| `playwright` | local | disabled | Launches `@playwright/mcp` via the module's Node-aware `npx` wrapper for browser automation |
| `notion` | remote | disabled | Hosted Notion MCP endpoint using OAuth |
| `serena` | local | disabled | Launched via `uvx` from the upstream repository |
| `sentry` | remote | disabled | Hosted Sentry MCP endpoint using OAuth |

## Installed skills

This repo also ships local skills for common tool-specific workflows. CLI
modules register bundled or repo-managed skills with `dotfiles.agentSkills`, so
rendering, patching, extension, and per-skill enablement happen uniformly at
build time. Current examples include:

- `architect`, for explicit design work and expensive-to-reverse boundaries; it
  does not trigger for routine features, clear-precedent placement, explanation,
  critique, implemented-diff review, or mere multi-file breadth
- `code-review`, for ordinary behavioral review of a named change. It judges
  stated intent and reachable behavior, distinct from `interrogate-me`
  adversarial review, `blast-radius` compatibility analysis, `how` architecture
  critique, and forge or PR workflows
- `test-curation`, for deciding which added or materially changed tests deserve
  permanent retention when finalizing code delivery
- `how`, for architecture and runtime explanations, and `why`, for
  evidence-backed investigations of intent and history
- `teach`, for paced explanations that build a mental model from mechanics and,
  when needed, rationale
- `recall`, for reconstructing current work state from live artifacts and bounded
  ctx history
- `reflect`, for evidence-backed lessons and proposed process or tooling
  improvements; it waits for approval before applying anything
- `interrogate-me`, for independent adversarial reviews routed through the
  shared `subagent-selection` policy; it returns a lead verdict without fixes
- `blast-radius`, for tracing compatibility and downstream breakage beyond a
  diff, then testing the assumptions that make the change safe
- `technical-writing`, for substantive engineering artifacts such as READMEs,
  tutorials, RFCs, and design docs; it adds document structure and technical
  accuracy while `impactful-writing` remains the general prose filter
- `impactful-writing`, for nearly all user-facing and durable prose, but not
  internal agent packets, raw tool output, or machine-consumed findings
- `jj-change-management`
- `jj-conflict-resolution`
- `jj-repo-workflow`
- `bay-workspaces`, for Bay-first repository acquisition and isolated checkout lifecycle; see [Bay](/docs/bay.md) for the operator model and [jj workspaces](/docs/jj-workspaces.md) for shared-engine details
- `linear-admin`, `linear-data`, `linear-git`, `linear-issues`,
  `linear-organization`, `linear-planning`, and `linear-tracking` (registered by
  `dotfiles.linearCli`)
- `rdny-browser` (registered by `dotfiles.rdny`)
- `gander-review` and `gander-address-review` (registered by `dotfiles.gander`)
- `sideshow-work-story`, for bounded work evidence gathering and impact-story
  synthesis, and package-backed `sideshow-deck-author`, for creating, revising,
  checking, building, reviewing, and publishing actual decks (both registered by
  `dotfiles.sideshow`)
- `srht-issues`, `srht-ci`, and `srht-setup` (registered by `dotfiles.srht`)
- `databricks-cli` (registered globally, currently disabled on `suremac`)
- `pup-cli`
- `rust-cargo` (registered by the OpenCode module through the shared skill
  registry; `dotfiles.devCache` appends host-specific sccache guidance so
  agents keep cargo output concise and never clear `RUSTC_WRAPPER`)
- `sure-stack-context` (suremac only)

Home Manager activation removes files left by the retired OpenCode PR-review
tools from `~/.config/opencode/tools/`.

When enabled, the `databricks-cli` skill notes that there is no
top-level `databricks sql` subcommand in the current official CLI. Agents
should use `queries`, `query-history`, `warehouses`, `psql`, or `databricks api`
depending on the task.

`suremac` additionally configures the `granola-meeting-context` skill so agents can pull
concise, redacted meeting-note context with the host-specific `granola` CLI when
relevant. The host-specific `pup-cli` skill gives agents compact Datadog CLI
patterns centered on `--read-only`, `--no-agent`, `--jq`, bounded queries, and
CSV/JSON output selection. `suremac` also installs `sure-stack-context`, a
Sure-specific investigation skill that routes between Datadog, Sentry, and
Kubernetes tools. Its company-specific service/ecosystem appendix is decrypted
from `secrets/opencode-sure-stack-context.age` and appended only to the local
installed skill, not stored in public docs or skill sources.

The jj skills recommend quiet/structured helper output for agents, especially
`jj sync -q --fail-on-conflicts` and `jj sync --json --fail-on-conflicts`.
When `jj lint` is not configured, agents should run `jj lint onboard --print`
to discover numbered candidate package, Python pyproject/tox/nox, Makefile,
justfile, Docker Compose, docs, CI, and pre-commit replacement workflows before
skipping validation. If only some suggestions are appropriate, persist exactly
those with `jj lint onboard --preview --select=1,3`, then persist with
`jj lint onboard --local --select=1,3` or
`jj lint onboard --write --select=1,3`.
Tracked `.jj-lint.toml` entries may be strings or `{ name, command }` tables;
omit `name` to use the inferred display label.

## OpenRouter API key

To provide an API key non-interactively, set:

```nix
dotfiles.opencode.openrouterApiKeyFile = "/run/agenix/openrouter-api-key";
```

The module exports `OPENROUTER_API_KEY` from that file in both Bash and Zsh shell initialization.

## CircleCI token

To provide a CircleCI token non-interactively, set:

```nix
dotfiles.opencode.circleciTokenFile = "/run/agenix/circleci-token";
```

The module exports `CIRCLECI_TOKEN` from that file in both Bash and Zsh shell initialization. This supports the `circleci` CLI and the optional OpenCode CircleCI MCP integration when enabled.

Local MCP servers that are distributed as npm packages use a repo-managed
`opencode-npx-mcp` wrapper instead of calling the Nix store `npx` executable
directly. The wrapper puts `node` on `PATH` for the MCP child process, which is
required because npm's `npx` launcher uses `/usr/bin/env node` internally.

On `suremac`, this relies on nix-darwin agenix secret materialization. The host
config sets explicit `age.identityPaths` for the user's SSH keys so Darwin can
decrypt shared secrets into `/run/agenix/` during activation.
