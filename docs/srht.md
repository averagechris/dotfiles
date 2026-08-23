# srht CLI

The `dotfiles.srht` Home Manager module installs `srht`, the SourceHut CLI for
builds, git, todo, lists, pages, paste, hub, webhooks, and GraphQL workflows.

## Repository issue tracker

Dotfiles work is tracked in the
[SourceHut projects tracker](https://todo.sr.ht/~averagechris/projects). The
tracker is shared across repositories, and dotfiles tickets are scoped with the
`repo:dotfiles` label.

From this checkout, pass the tracker explicitly when auto-detection has not yet
been configured:

```bash
srht --json todo list -t '~averagechris/projects'
srht --json todo show 169 -t '~averagechris/projects'
srht --json todo start 169 -t '~averagechris/projects'
```

The CLI automatically narrows umbrella-tracker reads to `repo:dotfiles` when it
can identify the checkout. Use `--all-repos` only when intentionally searching
across the whole tracker. Agents should load the `srht-issues` skill before
reading or changing tickets.

## Package source

The package comes from the upstream SourceHut flake:

```nix
inputs.srht.url = "sourcehut:~averagechris/srht";
```

The module defaults `dotfiles.srht.package` to
`inputs.srht.packages.${system}.srht` when that input is available. It imports
the upstream `programs.srht` Home Manager module and enables it when
`dotfiles.srht.enable = true`.

## Configuration and completions

The upstream v0.8.1 module supplies typed `programs.srht.instances` and
`programs.srht.profiles` options. The dotfiles wrapper extends its generated
document with cache, scoring, fallback, and optional legacy route settings while
keeping one `xdg.configFile."srht/config.toml"` owner.

The additional typed schema lives under `dotfiles.srht.settings` and covers
`cache`, `scoring`, `defaults` (including `doneResolution`), `todoFallback`,
`routePolicies`, `routes`, and the global `todoPolicy`. Nix uses camelCase
option names and renders srht's kebab-case TOML keys. By default it configures
the public `sr.ht` instance and lets `srht` use its normal OS keyring behavior.
For headless hosts, set `tokenCmd` instead of writing plaintext tokens into Nix:

```nix
programs.srht.instances = [
  {
    name = "sr.ht";
    tokenCmd = ["${pkgs.coreutils}/bin/cat" "/run/agenix/srht-token"];
  }
];
```

No token value option exists in either module. The generated document contains
only `token-keyring` or `token-cmd` when explicitly requested.

### Shared `work` profile

Enabling `dotfiles.srht` defines `programs.srht.profiles.work` and exports
`SRHT_PROFILE=work`. Profiles are explicitly selected bundles, not repository
matchers. The shared profile contains:

- the `sr.ht` instance;
- tracker and project `~averagechris/projects`;
- default done resolution `fixed`;
- `repo:{repo}` is added on create, filters reads unless `--all-repos` is used,
  and is required to exist on the umbrella tracker;
- exactly one work type is required from `chore`, `fix`, `feature`, `security`,
  `docs`, `refactor`, and `perf`;
- an optional estimate may use `points:1`, `points:2`, `points:3`, `points:5`,
  `points:8`, or `points:13`;
- exactly one of `severity:critical`, `severity:high`, `severity:med`, or
  `severity:low` is required only for `fix` and `security` work;
- `blocked`, `upstream`, `duplicate`, and `wontfix` are recognized workflow
  labels;
- create, update, and unknown-label validation warn, while existing-ticket
  validation is off to keep routine list reads quiet;
- unmatched repositories fail with `[todo-fallback] mode = "error"` rather
  than silently guessing a tracker.

The prior `personal-oss-projects` route and `projects` route policy were removed
because they only selected the same umbrella tracker and repository context
label now provided by the explicit profile. Routes remain supported under
`dotfiles.srht.settings` for future cases that genuinely need automatic
repository-to-tracker matching.

Select another configured profile globally or disable global selection with:

```nix
dotfiles.srht.activeProfile = "another-profile";
# or null to require --profile / SRHT_PROFILE from the calling environment
```

CLI `--profile` overrides `SRHT_PROFILE`. Repository bindings outrank a selected
profile; profiles outrank routes, defaults, and fallback selection. A profile's
todo policy also overrides a selected route policy.

After activation, validate and explain the effective configuration without
exposing credentials:

```bash
srht --profile work --json config check
srht --profile work --json todo context --repo '~averagechris/dotfiles' --explain
srht --profile work --json todo list --repo '~averagechris/dotfiles' --offline
```

The offline read requires a previously synchronized snapshot. The focused
`srht-config-rendering` flake check evaluates Home Manager and asserts the
profile, policy, selected environment variable, fallback, absence of routes,
and absence of token configuration in the rendered TOML.

The package ships bash, fish, zsh completions, and man pages under `share/`.
Adding the package to `home.packages` installs those completions into the Home
Manager profile for the configured shells.

## OpenCode skills

The srht module registers all bundled skills from the selected package's source
with the shared `dotfiles.agentSkills` renderer. All three are enabled by default:

- `srht-issues` - todo.sr.ht issue workflows
- `srht-ci` - builds.sr.ht CI submission, following, multi-job waiting, and logs
- `srht-setup` - auth, config, repository init, and cache refresh setup

Each skill has the same `enable`, `patches`, and `extraText` controls as skills
registered by other CLI modules. For example:

```nix
dotfiles.agentSkills.srht-setup.enable = false;
dotfiles.agentSkills.srht-ci.patches = [./srht-ci.patch];
```

See [`docs/opencode.md`](/docs/opencode.md) for the common renderer contract.

The module does not copy the skill text into this repository or run the mutable
`srht skills install` command during activation. After bumping `inputs.srht`, the
next Home Manager build links the upstream package source's updated skill text.

## Agent-facing CI additions

Manual manifests under `.srht/` are intentionally outside the auto-submitted
`.builds/` directory. `.srht/trainwreck-build.yml` preserves the native aarch64
trainwreck host build for manual retries with `srht ci .srht/trainwreck-build.yml --secrets`; hosted ARM startup failed twice before tasks, so it is not an
auto-submitted manifest until SourceHut ARM capacity is reliable.

`.srht/trap-diagnostics.yml` is a non-realizing trap host diagnostic: it uses
the standard Cachix secret/setup path,
prints effective Nix caches/builders, records disk and inode state, runs GC
root/dead-path reporting without deletion, times trap `drvPath` evaluation, and
compares trap build dry-runs with configured caches versus the official cache.
Submit it manually with `srht ci .srht/trap-diagnostics.yml --secrets`; it must
not mutate lock files or realize the trap closure.

`srht` v0.4 expands builds.sr.ht support for agents and polling automation:

- `srht builds wait ID... [--stdin]` follows multiple jobs at once, emits NDJSON
  transition events, periodic `heartbeat` snapshots, failed-task log tails, and a
  final `result`, and exits `10` when any job fails or times out. `--stdin`
  accepts newline-separated IDs, JSON arrays, or `srht --json builds list`
  output, so agents should prefer `builds list ... | srht --json builds wait
  --stdin` over shell polling loops.
- `srht builds status ID... [--stdin]` returns a one-shot JSON snapshot for one
  or more jobs and exits `0` on successful API reads, even when jobs are still
  running or have failed.
- `srht builds logs ID [--task NAME] [--tail N | --full] [--follow]
  [--timeout N]` prints or streams task logs, with NDJSON `log` events under
  `--json`.
- `srht builds list` now supports repeatable/comma-separated `--status`,
  repeatable ANDed `--tag`, and `--since DURATION` filters (`30m`, `2h`, `1d`,
  `1w`, etc.).
- `--logs` / `--logs-task NAME` on `srht ci`, `srht builds follow`, and `srht
  builds wait` interleave live log lines with status events. Multi-manifest
  `srht ci` runs also emit heartbeat snapshots via the shared polling core and
  accept `--interval` for heartbeat cadence.

## Enabled hosts

`suremac`, `tater`, and `thorny` enable `dotfiles.srht`. All three also add
`srht` to `dotfiles.opencode.agentTools`, so OpenCode agents see the SourceHut
CLI in their runtime tool note.

`thorny` configures `programs.srht.instances` with a `tokenCmd` that reads the
existing agenix-managed SourceHut token used by hut. `suremac` and `tater` use
the default keyring-backed srht authentication flow.
