# Linear CLI

The `dotfiles.linearCli` Home Manager module installs the `linear` CLI from the
`linear-cli` flake input and manages its non-secret context configuration for
agents.

## What the module manages

- Installs the configured Linear CLI package.
- Installs static bash, fish, and zsh completions when
  `dotfiles.linearCli.completions.enable = true`.
- Merges `dotfiles.linearCli.context` into the CLI's user-level `config.toml`
  during Home Manager activation.
- Writes `dotfiles.linearCli.hygiene` to the CLI's user-level `hygiene.toml`
  as a store symlink (the CLI only reads this file; snoozes and check
  artifacts live in its state directory).
- Optionally runs a periodic `linear context refresh` launchd job on Darwin.
- Optionally runs the hygiene automation suite on Darwin
  (`dotfiles.linearCli.hygieneAutomation`): scheduled report-cache
  refreshes, macOS notifications, shell/prompt nudges, and an agentic
  autofix job. See "Hygiene automation" below.
- Registers the CLI's seven bundled `linear-*` Agent Skills with the shared
  `dotfiles.agentSkills` renderer. Every skill is enabled by default and has
  standardized per-skill `enable`, `patches`, and `extraText` controls; see
  [`docs/opencode.md`](/docs/opencode.md).

`suremac` disables `linear-admin` while its upstream one-off API-key guidance is
unsafe for agent command arguments. The other six focused Linear skills remain
enabled.

The CLI resolves its user-level config directory with Rust's
`dirs::config_dir()`: `~/Library/Application Support/linear-cli` on macOS and
`$XDG_CONFIG_HOME/linear-cli` on Linux. The module targets that platform path;
files under `~/.config/linear-cli` on macOS are ignored by the CLI.

The activation merge intentionally preserves authentication/profile metadata in
the existing CLI config file. Credentials remain in the OS keyring via
`linear auth login`; the module only writes non-secret context and policy
hints. Legacy plaintext token values are blanked rather than removed. The
CLI's config parser requires `oauth.access_token` to exist.

## Hygiene rules

`dotfiles.linearCli.hygiene` manages the `[hygiene]` table consumed by
`linear hygiene check` / `fix` / `apply`. The default ruleset encodes the org
SDLC hygiene conventions (sdlc repo `scripts/linear/rules.py` and
`config/linear/cycles.yaml`), scoped to team `EPD` with the `ignore-audit`
exempt label:

- missing `domain` / `type` label on non-terminal issues
- missing priority on non-terminal issues; missing assignee on active issues
- missing estimate for issues in a cycle; off-fibonacci estimates (4, 6, 7,
  and above scale)
- staleness by status, approximating business-day thresholds as calendar
  durations (In Progress/Ready 5bd -> `7d`, QA 3bd -> `4d`, In Review 2bd ->
  `3d`); the In Review rule carries `nudge_review` / `move_back` fix options
- triage SLA: unprioritized or high-priority intake older than 1bd -> `2d`

Not expressible in the rule engine (comments and sub-issues are outside the
entity field model) and left to human sweeps: "canceled/duplicate without a
comment" and "estimate 8 without sub-issues".

The rule engine is self-documenting; when editing rules use:

```bash
linear hy rules --schema --output json   # field model + operator vocabulary
linear hy rules --init --rules PATH      # commented starter demonstrating operators
linear hy rules --rules PATH             # validate, listing all errors (exit 1)
```

Set `dotfiles.linearCli.hygiene = null` to manage `hygiene.toml` outside Home
Manager.

## Hygiene automation

`dotfiles.linearCli.hygieneAutomation.enable = true` (Darwin-only; launchd +
osascript) automates the hygiene loop around the local check artifact that
`linear hygiene check` writes to
`~/Library/Application Support/linear-cli/state/<profile>/hygiene-last-run.json`.
All schedules default to weekdays only.

| Job | Default schedule | What it does |
|-----|------------------|--------------|
| `linear-hygiene-refresh` | 10:00 and 16:00 | Refreshes the report cache with `linear hygiene check --mine --output json` |
| `linear-hygiene-summary` | 16:05 | macOS notification when any unresolved high/medium findings exist |
| `linear-hygiene-watch` | hourly 9:30-18:30 | Re-checks and notifies about high findings not previously seen (deduped in `~/.local/state/linear-hygiene/notified-high.json`; a finding that resolves and reappears notifies again) |
| `linear-hygiene-autofix` | 10:20 and 16:20 | Agentically resolves low-stakes findings (see below) |
| `github-pr-hygiene-refresh` | every 30 minutes 9:00-18:30 | Refreshes a cached `jj pr hygiene --json` report for open GitHub PR follow-up |

Logs land in `~/Library/Logs/linear-hygiene-*.log`. All the job entry points
are installed as commands, so any of them can be run manually
(`linear-hygiene-refresh`, `linear-hygiene-notify summary`,
`linear-hygiene-autofix`, `github-pr-hygiene-refresh`,
`github-pr-hygiene-report`, ...). GitHub PR hygiene logs use
`~/Library/Logs/github-pr-hygiene-refresh.log`, while the cache lives at
`~/.local/state/linear-hygiene/github-pr-hygiene-last-run.json`.

### Shell integration

- **Starship prompt hint** (`shell.promptHint.enable`): shows a compact
  `⚑<high> ~<medium> PR<count>` segment while unresolved Linear high/medium
  findings or actionable GitHub PRs exist in the local artifacts. Prompt reads
  are local-only and use `jq` rather than Python; they do not hit Linear,
  GitHub, or jj. The PR count includes PRs classified as `needs-fix`, `ready`,
  or `needs-review` by `jj pr hygiene` and is hidden when PR hygiene automation
  is disabled, the PR cache is expired, or it was generated with different
  configured search/limit/TTL/workdir/`no-workspaces` inputs.
- **New-shell greeting** (`shell.greeting.enable`): interactive zsh shells
  print a small fun report (counts, worst high findings, per-rule medium
  rollup, actionable PRs, and a nudge) when findings or actionable PRs exist.
  Rate-limited to once per `shell.greeting.minIntervalMinutes` (default 1, which
  only suppresses same-minute bursts like a batch of tmux panes; 0 prints on
  every shell); disable per-shell with `LINEAR_HYGIENE_GREETING=0`. Skips Linear
  artifacts older than 7 days and skips PR output entirely when PR hygiene is
  disabled; otherwise it skips expired or input-mismatched PR caches.

Note the artifact reflects whatever the *last* check wrote: a manual org-wide
`linear hy check -t EPD` temporarily swaps the prompt/greeting data source
until the next scheduled `--mine` refresh.

For the adjacent GitHub PR follow-up sweep, `github-pr-hygiene-report` is the
cached on-demand entry point. It refreshes the cache only when the TTL has
expired or the requested search/limit/TTL/workdir/`--no-workspaces` flags differ
from the cached inputs; pass `--force` to bypass the TTL, or `--json` for the cached JSON. The
underlying direct GitHub query is still `jj pr hygiene`, which reports open PRs
authored by the current GitHub user with status, review effort, priority, links,
and related jj workspaces; see [jj PR workflow](/docs/jj-pr-workflow.md#hygiene).
The PR cache is sensitive local metadata (repo names, PR titles/URLs, review
comment excerpts, and workspace paths), so the refresh script writes the state
directory as `0700` and the artifact as `0600`.

### Agentic autofix

`linear-hygiene-autofix` handles only low-stakes rules where a
wrong-but-reasonable value is cheap to correct:

- `issue-missing-domain`, `issue-missing-type` (label groups)
- `missing-estimate-in-cycle` (fibonacci estimate)
- `missing-priority`

The agent harness only *decides*; the script fetches issue context
(`linear i get`) and allowed label-group options (`linear context options`),
sends one batched prompt, then validates every decision against allowed
values (fibonacci estimates, existing group labels, priority 1-4) and applies
updates itself via `linear i update`. The agent is instructed to skip
genuinely unclear cases; unparseable or invalid decisions are dropped. Label
updates merge with existing labels because `linear i update -l` replaces the
label set. Findings are retried at most 3 times (tracked in
`~/.local/state/linear-hygiene/autofix-attempts.json`), and each run caps at
`autofix.maxFindings` (default 8).

The harness defaults to an affordable model via OpenCode and is swappable
(for pi later) through `autofix.agentCommand`:

```nix
dotfiles.linearCli.hygieneAutomation.autofix.agentCommand = [
  "opencode" "run" "--model" "openrouter/openai/gpt-5.5" "--variant" "low"
  "--title" "linear-hygiene-autofix"
];
```

### Tuning

```nix
dotfiles.linearCli.hygieneAutomation = {
  enable = true;
  scopeArgs = ["--mine"];               # scope for all scheduled checks
  weekdays = [1 2 3 4 5];               # launchd Weekday values
  refresh.times = [{hour = 10;} {hour = 16;}];
  summaryNotification.time = {hour = 16; minute = 5;};
  watch = {startHour = 9; endHour = 18; minute = 30;};
  autofix.rules = ["missing-estimate-in-cycle"];  # narrow the autofix surface
    prHygiene = {
      enable = true;
      ttlMinutes = 45;
      limit = 50;
      refresh = {startHour = 9; endHour = 18; minutes = [0 30];};
      search = "author:@me is:pr is:open archived:false";
      workdirs = ["/Users/chris/projects/dotfiles" "/Users/chris/projects" "${config.home.homeDirectory}/sureapp"];
      noWorkspaces = false;
    };
};
```

## suremac defaults

`suremac` enables the module with the `inputs.linear-cli` package and configures
agent-facing Sure EPD conventions:

- Default team: `EPD`
- Default new-work status: `Backlog`; when the user clearly intends to work the
  issue immediately, agents may assign it to `me` and set status to
  `In Progress`
- Required label groups: exactly one `domain` and exactly one `type`
- Execution label default: `agentic`
- Optional suggestion groups: `lob` and `carrier`
- Fibonacci estimation rubric: `0, 1, 2, 3, 5, 8`
- Estimate and assignee required before cycle work
- Project/initiative discovery should fetch options and ask when ambiguous
- Daily background refresh of labels, projects, initiatives, statuses, and teams

These defaults are deliberately high-level. The module does not embed private
member mappings, repo ownership, or complete domain taxonomies; agents should use
`linear context options ... --output json --compact` to fetch current options
from Linear.

The Linear CLI invalidates some affected caches after mutations such as project
or label changes, but invalidation is not the same as repopulating the cache. If
an agent creates a project and needs it to appear in option discovery during the
same session, it should refresh the relevant resource explicitly:

```bash
linear context refresh projects --quiet --retry 3
```

The daily launchd job keeps the normal steady-state cache warm:

```nix
dotfiles.linearCli.cacheRefresh = {
  enable = true;
  intervalSeconds = 86400;
  resources = ["labels" "projects" "initiatives" "statuses" "teams"];
};
```

Logs are written to `~/Library/Logs/linear-cli-context-refresh.log`.

## Override pattern

Host or user configs can override the generated context:

```nix
dotfiles.linearCli = {
  enable = true;
  package = inputs.linear-cli.packages.${pkgs.stdenv.hostPlatform.system}.linear;

  context.defaults.status = "Triage";
  context.agent_instructions = [
    "Fetch current Linear options and ask before choosing ambiguous labels."
  ];
};
```

Repository-local `.linear.toml` files still take precedence at runtime because
the CLI merges user context with project context when `linear context` runs.

## Useful commands

```bash
linear auth login
linear config show
linear context --output json --compact
linear context options labels --group domain --output json --compact
linear context refresh labels projects initiatives statuses teams
linear context refresh projects --quiet --retry 3
linear doctor
linear hy check --team EPD --output json --compact
linear hy report --by owner
```
