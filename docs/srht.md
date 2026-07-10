# srht CLI

The `dotfiles.srht` Home Manager module installs `srht`, the SourceHut CLI for
builds, git, todo, lists, pages, paste, hub, webhooks, and GraphQL workflows.

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

The upstream module writes `~/.config/srht/config.toml` from
`programs.srht.instances`. By default it configures the public `sr.ht` instance
and lets `srht` use its normal OS keyring behavior. For headless hosts, set
`tokenCmd` instead of writing plaintext tokens into Nix:

```nix
programs.srht.instances = [
  {
    name = "sr.ht";
    tokenCmd = ["${pkgs.coreutils}/bin/cat" "/run/agenix/srht-token"];
  }
];
```

The package ships bash, fish, zsh completions, and man pages under `share/`.
Adding the package to `home.packages` installs those completions into the Home
Manager profile for the configured shells.

## OpenCode skills

By default, `dotfiles.srht.opencodeSkills.enable = true` runs this during Home
Manager activation:

```bash
srht skills install --dir ~/.config/opencode/skills --force
```

This installs all bundled srht agent skills as OpenCode skills, currently:

- `srht-issues` - todo.sr.ht issue workflows
- `srht-ci` - builds.sr.ht CI submission, following, multi-job waiting, and logs
- `srht-setup` - auth, config, repository init, and cache refresh setup

Set `dotfiles.srht.opencodeSkills.names` to a list of skill names to install a
subset, or set `dotfiles.srht.opencodeSkills.enable = false` to skip activation
installation.

The `srht-ci` skill is intentionally installed from the `srht` package during
activation rather than copied into this repository. After bumping `inputs.srht`,
the next Home Manager activation refreshes the local OpenCode skill content with
the upstream package's bundled skill text.

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
