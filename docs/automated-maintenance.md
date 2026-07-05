# Automated maintenance

This document captures the near-term and long-term plan for letting `thorny`
perform routine dependency maintenance for dotfiles and the small project fleet.
The goal is deliberately conservative: ship boring, deterministic updates to
`main` automatically, and stop cleanly when a human decision is needed.

## Goals

- Run dotfiles maintenance daily on `thorny`.
- Update flake inputs and the manifest-enrolled fixed-hash packages through the
  existing `update-flakes` tool.
- For every automated change, start from current `main`, make one coherent
  maintenance commit, run configured checks, and push only when everything is
  green.
- On failures, leave no dirty checkout, no growing stack of failed fix attempts,
  and enough logs/state for Chris or an agent to take over.
- Eventually apply the same model across personal projects for flake inputs and
  language package managers (`cargo`, Python, npm/pnpm/yarn), with per-project
  safety policies.

## Non-goals for the first pass

- No autonomous code editing beyond deterministic update commands.
- No speculative build-error fixing.
- No Python or npm dependency updates until each project declares its package
  manager, lockfile policy, and checks.
- No cargo dependency widening until projects declare whether they are libraries
  or applications and what compatibility policy they want.
- No home-grown notification system before the failure state is useful; systemd
  status and journal logs are enough for the first pass.

## Short-term plan

The first implementation should be a simple `thorny` systemd timer plus a script
that only handles the dotfiles happy path.

### Daily dotfiles loop

1. Acquire a lock under `/var/lib/thorny-maintenance/` so runs cannot overlap.
2. Maintain a dedicated jj checkout under
   `/var/lib/thorny-maintenance/dotfiles/`; do not reuse a human checkout.
3. Fetch `origin/main` and create a fresh empty working-copy change on top of
   that remote bookmark.
4. Run `update-flakes` from the checkout.
5. If there are no changes, record success and exit.
6. Reject any unexpected changed path. The initial allow-list is:
   - `flake.lock`
   - `flakes/**/flake.lock`
   - manifest-enrolled fixed-hash package files under `flakes/base-lib/packages/`
7. Run the documented maintenance gate from the checkout. Do not bake in a slow
   broad check until the gate has been measured and tuned.
8. If checks pass, describe the jj change as
   `chore: update flake inputs and manual packages`, move `main` to it, and push
   `main` with jj.
9. Record the pushed revision and leave the checkout clean on top of current
   `main`.

### Failure behavior

Failures are expected to be graceful and boring:

- The script exits nonzero so `systemd` records the failed unit.
- The run log goes to journald and to a durable per-run directory under
  `/var/lib/thorny-maintenance/logs/<timestamp>/`.
- A concise failure marker is written under
  `/var/lib/thorny-maintenance/state/last-failure.json` with at least the run id,
  phase, profile, exit status, checkout path, and log directory.
- Any unpushed maintenance change is abandoned before exit, so the next run starts
  from a clean `main` instead of accumulating failed attempts.
- The same failing upstream state may be retried on the next timer run, but each
  retry starts clean. Long-term work should add smarter cooldowns and issue/todo
  creation.

### Phase 0: make the gate fast enough

Before enabling unattended direct-to-`main` pushes, make the automated check gate
explicit and cheap enough to run every day. A full `nix flake check` is valuable,
but it is slow in this repo and should not be the first thing that makes the
maintenance loop unpleasant to operate.

The first gate is exposed as a flake app so it can be measured before wiring it
into unattended pushes:

```bash
nix run .#dotfiles-maintenance-gate -- --profile smoke
nix run .#dotfiles-maintenance-gate -- --profile thorny --log-dir /tmp/dotfiles-maintenance-gate
nix run .#dotfiles-maintenance-gate -- --profile no-build
nix run .#dotfiles-maintenance-gate -- --profile full
```

Profiles:

- `smoke` reads flake metadata and evaluates the top-level maintenance packages
  for the current system. This is quick local sanity only; it is not sufficient
  for unattended direct-to-`main` pushes.
- `thorny` runs `smoke` plus evaluation of the `thorny` system derivation path.
  This is still eval-only; it does not build the system closure.
- `no-build` runs the top-level `nix flake check --no-build`; on a cold cache,
  this can still be slow because it checks every exported host configuration.
- `full` runs the top-level `nix flake check` with builds enabled.

The future unattended timer must pass an explicit profile rather than relying on
the app default. `smoke` is intentionally the default for quick manual runs; the
first direct-to-`main` timer should use the measured `thorny` profile or a
stronger profile documented here before the timer is enabled.

Then add targeted build checks only where they buy confidence for automated
flake-input updates. If a broader check is needed, prefer one Nix invocation that
requests multiple attrs over several background `nix` commands; the Nix daemon
already schedules independent builds across available cores.

Parallelism guidance:

- Do not parallelize build-heavy checks with shell job control by default. It
  usually competes with the daemon's own scheduler, duplicates evaluation work,
  and makes logs harder to read.
- If checks are independent and mostly evaluation/network bound, consider a
  single wrapper that measures them first and only parallelizes the pieces that
  show real wall-clock wins.
- Lockfile update steps may be parallelizable later because separate flake
  directories are mostly independent, but keep the first version sequential for
  deterministic logs and easier recovery.

### Checks

The eventual stronger automated gate may still be one command:

```bash
nix flake check
```

Until that is fast enough, split the gate into a documented fast path and a
slower manual/agent path. Do not push auto-updates without at least the fast path
passing, and do not silently promote the slower path into the daily timer without
recording why the runtime is acceptable.

### Timer implementation notes

Before enabling the daily systemd service, make the operational contract concrete
in code and docs:

- **Durable logs:** invoke the gate with an explicit per-run log directory such
  as `/var/lib/thorny-maintenance/logs/$(date -u +%Y%m%dT%H%M%SZ)`; journald is
  useful for status, but the handoff should not depend on journal retention.
- **Failure marker:** write `/var/lib/thorny-maintenance/state/last-failure.json`
  atomically. Suggested fields: `run_id`, `started_at`, `phase`, `profile`,
  `exit_status`, `checkout`, `log_dir`, `head_before`, and `message`. Remove or
  archive it only after a successful run.
- **jj cleanup:** on every pre-push failure, abandon the unpushed maintenance
  change and return the checkout to a fresh empty working-copy commit on top of
  the fetched integration bookmark. The concrete cleanup sequence should be based
  on the recorded maintenance change id, e.g. `jj abandon <change-id>` followed
  by `jj new main@origin`, rather than relying on whatever `@` happens to be
  after an error.
- **Allow-list source:** keep changed-path validation data-driven. The first
  allow-list can be hard-coded in the timer script, but it must include only
  lockfiles plus package files enrolled in `manual-package-updates.json`; do not
  allow arbitrary `flakes/base-lib/packages/*.nix` changes unless the package is
  in that manifest.

### Operations

Useful commands on `thorny` after the timer exists:

```bash
systemctl status thorny-dotfiles-maintenance.timer
systemctl status thorny-dotfiles-maintenance.service
journalctl -u thorny-dotfiles-maintenance.service
ls -l /var/lib/thorny-maintenance
```

## Near-term expansion

After the dotfiles loop has run successfully for a while, add a data-driven
project manifest instead of hard-coding more repositories. Each project entry
should declare:

- repository URL and integration bookmark (`main` unless overridden),
- update classes enabled for that project (`flake`, `cargo`, `python`, `npm`),
- allowed changed paths,
- checks required before pushing,
- whether direct-to-main pushes are allowed or a review branch/PR is required,
- cooldown/retry policy after failures.

Conservative cargo support can come next for projects with committed lockfiles:

1. Run `cargo update` without editing `Cargo.toml`.
2. Allow only `Cargo.lock` changes unless a project explicitly opts into
   manifest edits.
3. Run the project’s declared checks, usually `cargo test` and `nix flake check`.
4. Push only if all checks pass.

Library dependency widening, Python constraint widening, and npm semver range
edits need project-level policy before automation touches manifests.

## Long-term vision

The long-term system should look more like a small maintenance controller than a
big shell script.

- `workctl` owns the project registry, per-project policies, check commands,
  checkout locations, and current maintenance state.
- The SourceHut CLI fork grows the pieces needed to create/update lightweight
  todos, tickets, build links, or patch artifacts when automation stops.
- Thorny runs scheduled maintenance rounds and records structured outcomes:
  updated, no-op, failed-update, failed-check, failed-push, or needs-human.
- Agents can pick up `needs-human` work from the structured state, inspect logs,
  make obvious fixes, and either ship or leave a clear note for Chris.
- Notifications become event-driven: daily summary when everything is green,
  immediate nudge only when a project enters or remains in `needs-human`.
- More update classes become safe through policy:
  - flakes: lockfile updates plus `nix flake check`,
  - Rust applications: lockfile bumps and optionally `cargo update -p`,
  - Rust libraries: explicit dependency range widening only when tests and
    semver policy allow it,
  - Python: tool-specific lock refreshes (`uv`, Poetry, pip-tools) before
    manifest widening,
  - npm/pnpm/yarn: lock refreshes first; manifest range changes only when a
    project opts into app-style bumping or library-style widening.

The key invariant should remain the same at every maturity level: automation may
ship boring green updates, but any ambiguous failure must stop with clean state
and a useful handoff instead of piling up broken attempts.
