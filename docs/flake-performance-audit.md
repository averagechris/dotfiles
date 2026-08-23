# Flake performance audit

This summarizes the 2026-07-09 Nix flake performance audit and follow-up
burn-down tracked in SourceHut.

## Conclusion

No evidence yet justifies a wholesale rewrite. The root fleet scope, confirmed
import-from-derivation (IFD), checks and CI shape, cache policy, and QEMU
emulation are stronger suspects than multi-flake boundaries alone. Treat
architecture changes as a measured decision, not a premise.

## Baseline measurements

Measured on suremac with the eval cache disabled. These numbers are
directional, not rigorous.

- Root `nix flake check --no-build`: 2.45s, about 2.2 GB max RSS; this
  covered native Darwin only.
- Warm/offline `drvPath` evals: tater 17.78s, thorny 9.57s, trap 5.69s.
- Initial `drvPath` evals: tom 4.17s, cruber 6.65s, trainwreck 6.01s,
  taz 2.95s, tootsie 2.32s, suremac 6.51s.

Earlier tater and thorny runs were network-influenced, so use the warm/offline
numbers for comparisons.

## Confirmed issue

tater and thorny fail with `allow-import-from-derivation = false`. The
confirmed IFD source is the Cantarell workaround in
`flakes/base-lib/overlays/default.nix`.

Update for SourceHut #116: this workaround was removed after verifying that the
pinned nixpkgs revision `d407951447dcd00442e97087bf374aad70c04cea` includes the
NixOS/nixpkgs #535887 fix in `python3Packages.afdko`. tater and thorny now
evaluate with `allow-import-from-derivation = false`.

## SourceHut #116 benchmark note

Measured on suremac from outside the checkout with `flake-benchmark`, eval cache
disabled, offline samples, one warmup, and three measured runs per host. These
are dirty/directional local numbers: the before run was a clean checkout at
revision `6c5ef44d2bf3`; the after run used the dirty #116 workspace at revision
`949733588ad8` before docs were updated. Treat the comparison as confirmation
that removing the IFD did not regress evaluation, not as a rigorous performance
claim.

| Target | Before elapsed samples / mean | Before RSS mean | After elapsed samples / mean | After RSS mean |
| --- | ---: | ---: | ---: | ---: |
| `host:tater` | 34.32s, 34.44s, 32.40s / 33.72s | 1751 MiB | 21.91s, 22.59s, 22.83s / 22.44s | 1584 MiB |
| `host:thorny` | 35.96s, 35.49s, 38.18s / 36.54s | 1458 MiB | 22.61s, 22.87s, 23.58s / 23.02s | 1385 MiB |

Raw JSONL outputs were stored outside the checkout for local analysis and were
not committed.

## Ranked findings

1. The root flake exports nine full systems, so root checks have fleet-wide
   evaluation scope.
1. IFD is confirmed and should be removed or isolated before broader
   architecture conclusions.
1. Check definitions duplicate package sets and source scope, increasing eval
   and realization pressure.
1. CI appears duplicated, and existing comments point to OOM pressure.
1. The lock graph contains duplicate inputs worth de-duplicating.
1. Cache behavior is fragmented; thorny realization was local-only in observed
   runs and needs cache/warmer policy work.
1. trainwreck uses QEMU, likely a build-time bottleneck separate from eval.

## Hosted SourceHut policy from #121

SourceHut is the only repository CI surface, but hosted runners are not the
operational full-closure builder. The #121 trap diagnostic
([job 1817195](https://builds.sr.ht/~averagechris/job/1817195)) measured the
hosted `nixos/unstable` x86_64 runner as a single 16G filesystem with about 13G
free at job start. A non-realizing dry-run for `trap` planned 853 local builds and
1696 fetched paths, about 4.8 GiB download and 13.2 GiB unpacked. Comparing the
official cache only still planned about 4.8 GiB download and 13.3 GiB unpacked,
so adding caches reduced build count but did not make the unpacked volume safe
for the runner once build temp space is considered. Trap eval itself completed in
253.31s with about 1.7 GiB max RSS.

Therefore ordinary hosted SourceHut CI must not realize complete host closures.
It checks shared code, evaluates all important hosts, and builds only targeted
high-signal checks. `thorny` remains the operational closure builder and cache
warmer for fleet realization. Full fleet or host-closure builds are manual paths
for larger/recovered runners.

## Thorny warmer update from #121

The `dotfiles-host-build-cache` service on thorny is now revision-aware. It
resolves SourceHut `main` once per service run, validates the 40-character Git
revision, builds all active NixOS hosts from that revision-pinned flake URL, and
records `last-successful-rev` atomically only after all six hosts succeed. A
subsequent timer run for the same revision skips before any Nix evaluation.

The implementation intentionally preserves per-host `nix build` invocations,
result roots, and logs. That keeps failure isolation and bounds peak evaluator
memory; the measured multi-installable speedup below is not worth its much higher
and variable peak RSS for the recurring unattended service.
The service logs effective Nix environment details and separates elapsed timing
for the five x86 hosts from trainwreck's aarch64/QEMU build. Trainwreck also has
a best-effort dry-run planning diagnostic, but diagnostic failure does not mask
the actual build result.

For reproducible local exploration without triggering huge builds, use:

```bash
nix run .#host-build-cache-benchmark -- --rev <40-char-sourcehut-main-rev>
```

The harness compares the complete five-host sequential x86 loop with one
multi-installable dry-run at the same pinned revision, disables the evaluation
cache, alternates execution order, and prints elapsed time and max RSS. Dry-run
output can show planning/evaluation/substitution differences, but it cannot prove
realized build throughput, scheduler behavior, or QEMU impact.
The five-system dry-run can itself take tens of minutes, so it remains an
explicit operational benchmark rather than a routine CI check.

### 2026-07-09 thorny results

The harness ran twice against pinned revision `48581c55246d`, alternating order:

| Run | Shape | Elapsed | Max RSS |
| --- | --- | ---: | ---: |
| 1 | sequential five-host loop | 135.91 s | 1,541,188 KiB |
| 1 | one multi-installable invocation | 58.81 s | 2,496,692 KiB |
| 2 | one multi-installable invocation | 60.47 s | 3,934,088 KiB |
| 2 | sequential five-host loop | 136.65 s | 1,540,644 KiB |

The multi-installable dry-run was about 2.3 times faster, but peak RSS ranged
from 2.4 to 3.8 GiB versus a stable 1.5 GiB for the sequential loop. Keep the
sequential warmer: predictable memory, per-host logs, and failure isolation are
more valuable than reducing an already revision-gated background run by roughly
one minute.

The first deployed revision-aware warmer run completed in 111 seconds wall time:
107 seconds for the five x86 hosts and 3 seconds including trainwreck planning.
The cached trainwreck realization itself was 0 seconds. The immediately repeated
run skipped before Nix evaluation and returned through SSH in 1.45 seconds.

To measure a real ARM miss, revision `eb29b3ae6155` temporarily added a tiny C
program compiled by an `aarch64-linux` derivation in the trainwreck closure. The
dry-run reported 18 derivations requiring local builds, including
`trainwreck-qemu-probe-2026-07-10`; Thorny then realized the trainwreck closure
through binfmt/QEMU in 63 seconds (67 seconds including the diagnostic dry-run).
The complete service used 1.4 GiB peak RSS and 207 seconds wall time. The probe
binary ran successfully on Thorny through binfmt, and its derivation metadata
reported `system = aarch64-linux`. The probe was removed immediately afterward.

This controlled miss does not justify native ARM infrastructure. A roughly
one-minute occasional QEMU penalty is acceptable for the six-hour background
warmer, and no emulation failure or memory pressure occurred. Revisit native ARM
only if larger natural misses become frequent or unreliable.

## Check tiers from #120/#121

Fast ordinary CI is separated from explicit fleet validation instead of running
root `nix flake check` for every push:

1. **Fast lint/shared checks**: `.builds/lint-check.yml` runs
   `scripts/ci-check-tiers.sh fast`: Alejandra format check, Statix, ShellCheck
   over tracked `*.sh` files, and eval-only checks for shared flakes. Shared fast
   checks pass `--no-write-lock-file`.
2. **Active NixOS host evals**: `.builds/active-host-evals.yml` runs
   `scripts/ci-check-tiers.sh active-host-evals`, evaluating drvPaths for `trap`,
   `thorny`, `tom`, `cruber`, `tater`, and `trainwreck` as separate sequential
   Nix processes with `--no-write-lock-file` and `--option eval-cache false`. It
   does not build or download full host closures. Inactive `taz` and `tootsie`
   are intentionally excluded. The filename is retained for continuity with
   SourceHut job names, but the tier is eval-only.
3. **Coverage checks**: `.builds/coverage-checks.yml` runs
   `scripts/ci-check-tiers.sh coverage-checks` on x86_64 Linux. It evaluates
   suremac's Darwin system with an eval-only `nix eval --raw` command and builds
   the five current explicit desktop checks: tater static desktop, tater
   greeter/home Hyprland configs, and thorny greeter/home Hyprland configs.
   suremac remains eval-only because building a Darwin closure on Linux is not
   practical or high-signal for this CI shape.
4. **Manual native trainwreck build**: `.srht/trainwreck-build.yml` sets
   `arch: aarch64` and runs `scripts/ci-check-tiers.sh trainwreck-build`. It is
   outside `.builds/*.yml` because two hosted ARM jobs failed before any task logs
   were produced, so auto-submitting it guaranteed red CI without testing code.
   Retry manually with `srht ci .srht/trainwreck-build.yml --secrets` after
   SourceHut ARM capacity recovers or when explicitly diagnosing the runner.
5. **Manual full fleet**: `.srht/full-fleet.yml` runs the root
   `nix flake check --accept-flake-config`. It intentionally lives outside
   `.builds/*.yml` because git.sr.ht auto-submit should remain bounded. Submit it
   manually with `srht ci .srht/full-fleet.yml --secrets` or from an external
   schedule when comprehensive realization is required; `--secrets` is needed
   because `scripts/ci-setup.sh` expects `~/.ci_secrets/cachix_token`, and srht
   CLI noninteractive submissions withhold manifest secrets unless explicitly
   enabled. It may still fail on hosted VMs until a sufficiently large external
   runner or different operational schedule is used.
6. **Manual trap diagnostic**: `.srht/trap-diagnostics.yml` is a one-off
   non-realizing disk/cache diagnostic path for reproducing the #121 measurement
   shape without mutating lock files or realizing trap.

git.sr.ht ordinary pushes auto-submit exactly three bounded `.builds/*.yml` jobs:
`lint-check.yml`, `active-host-evals.yml`, and `coverage-checks.yml`. Submit manual
manifests separately when needed:

```bash
srht ci .srht/full-fleet.yml --secrets
srht ci .srht/trainwreck-build.yml --secrets
srht ci .srht/trap-diagnostics.yml --secrets
```

If SourceHut scheduling is configured outside the repository, schedule manual
`.srht/` manifests there with equivalent secret exposure for the Cachix token
rather than adding unsupported trigger syntax to the manifest.

After this lands, measure duration and max RSS with the same benchmark discipline
as #117: compare SourceHut job wall time and failed-task logs by manifest, and
use `nix run .#flake-benchmark -- --target root-check --target all-hosts` on a
stable runner when local eval-only RSS trends are needed. Treat substitution and
build timing separately from eval-only timings.

## Interpreting performance

Keep evaluation, substitution, and builds separate:

- Evaluation: Nix computes derivations and output graphs. The `drvPath` and
  `flake check --no-build` timings mostly exercise this.
- Substitution: Nix downloads available store paths from caches. Cache
  fragmentation or missing uploads can look like build slowness.
- Builds: Nix realizes missing paths locally or remotely. QEMU and source-heavy
  checks mainly affect this layer.

## Repeatable evaluation benchmarks

SourceHut [#117][issue-117] adds a root app for reproducible evaluation-only
measurements:

```bash
nix run .#flake-benchmark -- --help
nix run .#flake-benchmark -- --list-targets
nix run .#flake-benchmark -- --target root-check --runs 5 --warmup 1 \
  --output /tmp/dotfiles-flake-benchmark.jsonl
nix run .#flake-benchmark -- --target host:tater --runs 3 --warmup 1 \
  --output /tmp/tater-eval.jsonl
```

If no `--target` is supplied, the default target set is `root-check` plus all
configured hosts. `--target` is repeatable and accepts:

- `root-check`: `nix flake check --no-build`, which evaluates checks but does
  not realize them.
- `host:<name>`: host system derivation evaluation only (`drvPath` for NixOS
  hosts, Darwin system evaluation for `suremac`).
- `all-hosts`: every configured host target.

Useful options:

- `--runs N`: measured samples per target.
- `--warmup N`: warmup samples per target. Warmups are recorded as JSONL rows
  with `phase="warmup"`; exclude them from comparisons unless intentionally
  studying cache effects.
- `--output PATH`: write JSON Lines to a file instead of stdout. Parent
  directories are created if needed. Put output outside the benchmarked
  checkout; paths inside `--repo` are rejected so the benchmark does not change
  dirty/source state.
- `--prepare`: run an online preparation phase before warmups and measured
  samples. Preparation rows use `phase="prepare"` and are not comparable
  measurements. If preparation fails, the failed row is recorded, stderr is
  replayed to the benchmark process stderr, and the command exits nonzero before
  comparable measured samples start.
- `--offline` / `--no-offline`: measured and warmup samples default to
  `--offline`; preparation is always online.
- `--allow-dirty`: allow benchmarking a dirty checkout and record
  `dirty=true`. Without this, the tool refuses dirty checkouts.
- `--repo PATH`: benchmark a checkout other than the current directory.

Every measured Nix command passes `--no-write-lock-file` and
`--option eval-cache false` to avoid mutating lock files and to keep samples
comparable. The implemented workflow deliberately measures evaluation only.
Substitution dry-runs and build/realization timings are future explicit work,
not part of #117, because they answer different cache and builder questions.

### JSON Lines schema

The output starts with one metadata record, followed by one record per sample.
All records include `schema="dotfiles.flake-benchmark.v1"` and ISO-8601 UTC
`timestamp` values.

Metadata fields:

- `record`: `"metadata"`.
- `revision`: jj working-copy commit when available, with a git fallback.
- `dirty`: whether the checkout had local changes.
- `current_system`: `builtins.currentSystem` for the runner.
- `nix_version`: local Nix version.
- `nix_version_raw`: complete vendor-specific `nix --version` output.
- `substituters`: effective Nix `substituters` setting as reported by Nix.
- `trusted_public_keys`: effective signature keys as reported by Nix.
- `builders`: effective Nix `builders` setting as reported by Nix.
- `builders_use_substitutes`: effective remote-builder substitution policy.
- `flake_lock_sha256`: SHA-256 of `flake.lock`, or `null` when absent.
- `benchmark_config`: requested `runs`, `warmup`, default `offline`, and
  `prepare` values.
- `targets`: expanded target list.
- `eval_cache`: always `false`.
- `warmups_recorded`: `true` for this version.

Sample fields:

- `revision`, `dirty`, `current_system`, and `nix_version`: copied from the
  run metadata so individual rows remain self-describing.
- `target`: `root-check` or `host:<name>`.
- `phase`: `prepare`, `warmup`, or `measured`.
- `run`: 1-based sample index; preparation uses `0`.
- `warmup`: boolean convenience flag.
- `offline`: whether the sample used Nix `--offline`.
- `eval_cache`: always `false`.
- `elapsed_seconds`: GNU time elapsed wall-clock seconds.
- `max_rss_kib`: GNU time maximum resident set size in KiB.
- `exit_status`: command exit status. Failed samples are still recorded, and
  the benchmark exits nonzero if any measured sample fails. Failed commands also
  replay captured stderr to the benchmark process stderr; JSONL stays clean on
  stdout or in `--output`.

Validate output with:

```bash
jq -c . /tmp/dotfiles-flake-benchmark.jsonl >/dev/null
```

### Clean-checkout and platform caveats

For comparable numbers, run from a clean checkout (or pass `--allow-dirty` only
for exploratory local work), keep the same Nix version, and avoid concurrent
CPU-, memory-, or I/O-heavy tasks. The app records dirty state and revision, but
it cannot normalize thermal throttling, laptop power state, filesystem cache,
remote cache availability, or Nix daemon contention.

GNU time is used for elapsed time and max RSS on both Darwin and Linux. RSS
accounting may still differ by kernel, so compare trends within one platform
first. Offline samples reduce network noise but require needed inputs and store
metadata to already be present; use `--prepare` for an explicit online preflight
when starting from a colder checkout.

## SourceHut burn-down

Umbrella: [#115 Nix flake performance audit][issue-115]

Child issues in burn-down order:

1. [#117 Establish repeatable benchmarks][issue-117]
1. [#116 Remove or isolate confirmed IFD][issue-116]
1. [#120 Define check tiers][issue-120]
1. [#118 Reduce duplicate check work][issue-118]
1. [#119 Simplify the input graph][issue-119]
1. [#121 Improve caches and warmers][issue-121]
1. [#122 Architecture decision gate][issue-122]

## Architecture decision gate

Use [#122][issue-122] as a measurement gate after the preceding work. Compare:

- Optimized current multi-flake layout.
- Lightweight developer root plus a separate fleet flake.
- Monoflake or flake-parts consolidation.

Only choose a larger architecture change if repeatable measurements show it
beats the optimized current design for the workflows that matter.

[issue-115]: https://todo.sr.ht/~averagechris/projects/115
[issue-116]: https://todo.sr.ht/~averagechris/projects/116
[issue-117]: https://todo.sr.ht/~averagechris/projects/117
[issue-118]: https://todo.sr.ht/~averagechris/projects/118
[issue-119]: https://todo.sr.ht/~averagechris/projects/119
[issue-120]: https://todo.sr.ht/~averagechris/projects/120
[issue-121]: https://todo.sr.ht/~averagechris/projects/121
[issue-122]: https://todo.sr.ht/~averagechris/projects/122
