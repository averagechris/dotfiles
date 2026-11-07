# Automated maintenance

Michi coordinates a dedicated Thorny maintenance controller. GitHub prepares
updates and validates native systems. A fresh Sol 6.1 high review judges the
change, upstream evidence, and temporary holds. GitHub independently verifies
evidence before eligible changes can merge. Routine successes stay quiet;
problems go to Chris's private Telegram DM.

## Staged state

The implementation ships disabled. `dotfiles.maintenance.enable` defaults to
false, policy `merge_enabled` is false, and workflows require approved repository
variables. While disabled the module creates no maintenance users, services,
timers, credentials, or extra bot access. The former direct-to-main timer proposal
is superseded by this PR/evidence workflow. A smoke gate or updater exit never
authorizes an automatic merge.

## Boundaries and lifecycle

The owner DM can use `michi-maintenance run`, `status`, `pause`, or `resume`.
Guests and groups have neither shell nor the maintenance command. The wrapper
only records fixed requests or reads bounded status. The dedicated controller
does not borrow the bot's owner token, browser, Codex login, or unrelated memory.
It mints short-lived App tokens narrowed to Actions write, Contents read, and
Pull requests read. Its token cannot push or merge.

The opt-in timer polls every 15 minutes and starts at most one scheduled candidate
per weekday after 09:00 UTC, at least 23 hours apart. Explicit owner requests can
start sooner. Six-hour heartbeats continue while paused; missed work does not
cause a burst of catch-up generations.

1. Resolve current main, trusted policy hash, and a unique run identifier.
2. Run the trusted-base Rust updater in a secretless GitHub job with normal
   cooldowns. Coordinate named shared inputs across all 15 canonical locks, then
   refresh local path parents offline. Preserve original URLs, explicit revisions,
   version tags, local topology, and suremac's separate Helix graph. Native Darwin
   validation builds both suremac and taro, while the Keychain attestation remains
   specific to suremac. Only enrolled Pi/Helium version and hash updates are
   eligible package edits.
   Coordination applies to the same original input; a host-specific explicit pin
   (such as Thorny's memo input) stays distinct and cannot be advanced by syncing.
3. A separate publisher rechecks allowed bytes and creates one commit/PR through
   GitHub blob/tree APIs. It never executes candidate code, overwrites a differing
   branch, or reopens a closed matching PR. No-op generation creates no PR.
   A replacement closes older untouched App maintenance PRs; extra commits stop
   replacement for owner review. Local path inputs refresh in dependency order.
4. Validate exact base/head/policy and clean checkout on x86_64 Linux, ARM64 Linux,
   and ARM64 Darwin. Run base-versus-candidate warning comparison with the same
   Nix version, lint, native full-host builds, flake checks, and forced OpenCode
   node_modules rebuilds. Reject flake-supplied configuration and require Nix
   sandboxing. Candidate uv additionally runs in a filesystem/process sandbox.
   The trusted prepare job verifies ancestry once with authenticated GitHub reads;
   native shards require that exact-revision proof. Lint runs on x86_64 Linux.
   A missing, skipped, failed, or stale platform cannot count as green.
5. Gather trusted repository context, the complete allowed patch, comparisons
   for changed canonical locks, enrolled release metadata, and native evidence.
   Large comparisons explicitly label their bounded commit sample. Uncovered
   legacy/new sources and oversized context require owner review.
   Existing channel tarballs may retain their recorded redirect target; changing
   those locked bytes requires owner review rather than a guessed source identity.
6. Call the Responses API with gpt-6.1-sol, high reasoning, structured output,
   and store=false. The model has no tools, shell, plugins, credentials, or resumed
   author session. No global Michi model or existing Codex profile changes. It
   returns merge, hold, or needs_owner, with reasons, sources, concerns, and every
   hold's decision. Model success alone is never sufficient evidence.
   With policy merging disabled, a passing review completes a dry run without
   dispatching a merge workflow; its review remains available in private state.
   The output cap is 32,768 tokens including reasoning; the socket deadline is
   ten minutes. Confirm those bounded costs in the API budget before enablement.
7. The merge workflow re-fetches PR/files/policy, native and host artifacts,
   freshness, hashes, required branch rules, and App bypasses. Require strict
   server-side Maintenance / native evidence checks from GitHub Actions and PRs
   on main. The calling token must report `current_user_can_bypass=never` for
   every applicable ruleset; unknown access blocks. Merge only
   the exact head SHA; an advanced base requires regeneration. A candidate cannot
   alter its own acceptance policy.
8. Reconcile the actual PR result. Persist uncertain dispatch/merge outcomes and
   query GitHub before allowing new work. A timeout never proves nothing executed.
   An interrupted review stops rather than silently reusing old context.
   Superseded generations end quietly. Completed decision runs settle from the
   exact PR state; missing runs stay latched until their review can no longer
   pass the freshness gate. Owner run requests remain pending while busy/paused
   or through temporary API failures. Temporary failures retry and alert after
   an hour rather than permanently stopping future scheduled work.

Arbitrary module repairs, policy/CI edits, credentials, deployment logic, and
boot/storage/network/auth changes need Chris's review. Broader compatibility
failures produce a handoff instead of an unbounded speculative repair loop.
This initial scope does not promise to repair every upstream breakage. These
boundaries narrow maintenance, not the owner's separately accepted general shell
privileges.

## Contextual holds

maintenance/policy.json records safety intent and acceptance evidence. The agent
may recommend automatic release when those conditions are proved, but cannot
weaken them. Policy comes from the trusted base; the candidate supplies evidence.

The certificate hold retains nixpkgs e4d4e5154c52da44a9e5a4895d270cffa1ecb6fc
until a candidate proves cacert >=3.131.1, uv >=0.13.4, ancestry containing the
recorded certificate/cacert/System76 fixes, and the declared native probes.
Both rejection endpoints must yield curl error 60 with candidate package/Linux
system bundles, while healthy HTTPS succeeds. Actual candidate uv must trust a
temporary CA through SSL_CERT_FILE without opt-in, then reject a different valid
CA. It resolves an inert wheel with --dry-run; nothing installs or executes.
Versions alone do not prove this behavior.

Darwin CI proves its package bundle and uv behavior, not a Linux system bundle
or workstation Keychain result. A separately approved suremac attestor must prove
both the actual system bundle and the Nix daemon's independently exported Keychain
bundle, with fresh evidence bound to the exact candidate and policy:

```sh
PYTHONPATH=scripts python3 -m maintenance.cli attest \
  --trusted . --identity /approved/tmp/evidence.json \
  --curl /nix/store/<trusted-curl-output>/bin/curl \
  --output /approved/tmp/host-evidence.json
```

Get identity from the trusted validation run, run on suremac from a trusted
checkout, and submit its JSON through maintenance-attest.yml as the approved
attestor. The required curl path must be the trusted base's immutable Nix-store
curl executable using OpenSSL; the command checks its backend before probing.
This avoids Darwin's system curl selecting SecureTransport even when `--cacert`
is supplied. Then request a fresh review. The task creates or borrows no identity.
Missing host evidence retains the hold; routine attestor work gets a one-hour
grace period before alerting Chris. Host evidence measures the currently activated
Mac's system and exported Keychain bundles using the trusted Nix-store OpenSSL
curl. It does not attest the candidate's future system bundle. Binding it to the
candidate identifies which decision may use this environmental observation;
candidate certificate bytes and uv behavior are separately proved by Darwin CI.
It does not cover every browser/application-bundled store;
see [manual package updates](manual-package-updates.md). Conditions continue
protecting subsequent updates until policy is explicitly revised.

For routine operation, the separate opt-in `dotfiles.maintenanceAttestor` Darwin
module polls every 15 minutes while suremac is awake. It validates the candidate
and CI evidence, measures the actual bundles, submits through the authorized
workflow, and deduplicates submissions for 20 hours. The controller waits for it
and continues automatically when evidence arrives. No per-update manual probe is
needed. The module defaults off and requires a newly approved, repository-scoped
fine-grained user token with Actions write, Contents read, and Pull requests read,
stored in an explicit mode-0600 file. It verifies the token's user login and never
falls back to the workstation's GitHub credentials. It has no OpenAI or Telegram
credential. Manual attestation remains available for diagnosis.

## Alerts and recovery

The private durable outbox records issues before delivery, deduplicates by
candidate/failure fingerprint, and reminds after 24 hours if unresolved. Noop,
merged, and recovered classes stay quiet. Alerts explain the problem and needed
action with a PR/run link. The notifier alone receives fixed-owner Telegram
credentials. Transient/rate-limit failures retry with backoff; permanent rejection
keeps the notifier failed until delivery succeeds. Unresolved rejected events can
retry after the same 24-hour reminder window, so fixing access restores delivery.
Both host and
GitHub use the same delivery command, which logs only counts and fails visibly
on retry or permanent rejection. Lost acknowledgements may produce a duplicate.

An independent GitHub watchdog checks an 18-hour heartbeat threshold every six
hours. Its cached outbox retains retries/deduplication and drains after recovery.
The cache contains bounded public alert metadata, never credentials, owner IDs,
prompts, or logs. Delivery failures fail Actions visibly. Cache retention and
Telegram availability are not an always-deliver/exactly-once guarantee.

Pause stops new work, not a dispatched merge. Reconciliation and heartbeats
continue. Run/resume never bypass holds, checks, or uncertain outcomes. Private
state lives under /var/lib/dotfiles-maintenance. Inspect with michi-maintenance
status, systemctl status dotfiles-maintenance.service, and journalctl -u
dotfiles-maintenance.service. Never paste raw API errors or secrets.

## Provisioning and enablement

These actions need Chris's separate approval; this setup performs none:

1. Create/install a dedicated GitHub App on only averagechris/dotfiles, with
   Contents/Pull requests/Actions write, Metadata read, and no ruleset bypass.
   Put its key in approved root-readable host storage and the approved GitHub
   maintenance environment. The controller mints narrower tokens. Never substitute
   REPO_TOKEN or an existing owner token.
2. Provision a dedicated personal OpenAI API service key with agreed spending/rate
   limits and Sol access, only to the controller's openai-api-key credential.
   Subscription credentials are not copied to CI or switched to API billing.
3. Approve notifier bot-token/fixed-owner access and separate watchdog copies.
   Secrets: MAINTENANCE_APP_ID, MAINTENANCE_APP_PRIVATE_KEY,
   MAINTENANCE_TELEGRAM_BOT_TOKEN, MAINTENANCE_TELEGRAM_OWNER_ID.
   Variables: MAINTENANCE_APP_LOGIN, MAINTENANCE_HOST_ATTESTOR_LOGIN.
   Publisher, merge, and watchdog notifier jobs use the maintenance-merge
   environment; generator/native jobs get no secrets.
   Separately approve the narrowly scoped suremac attestor token and its Darwin
   launch agent; set the same authorized user login in both hosts and GitHub.
4. Approve strict required Maintenance / native evidence checks and PRs for main,
   pin the check to the GitHub Actions integration, read-only workflow defaults,
   and no maintenance App bypass. Existing owner bypass is a separate decision.
5. Review/merge setup separately. Configure Nix credential-file options and IDs.
   Approve enabling the controller and MAINTENANCE_ENABLED for controlled dry runs,
   while MAINTENANCE_AUTOMERGE and policy merging remain false.
6. Prove App publication, all native builds, real Sol output, hold/host probes,
   Telegram failure/retry, and restart recovery. Only then separately approve the
   reviewed policy change plus MAINTENANCE_AUTOMERGE=true. Never enable from a
   candidate. The controller key is used by fixed code, never a coding agent.

## Validation and rollback

```sh
python3 -m unittest discover -s tests -p 'test_maintenance_*.py'
python3 tests/test_self_deploy.py
nix build --no-link .#checks.aarch64-darwin.maintenance
```

The Nix check is also included in Linux CI coverage. Unit tests use fake
GitHub/model/Telegram transports and never create credentials, send messages,
update real locks, merge, or deploy. They do not prove live APIs, native full-host
builds, Linux bubblewrap, Darwin Seatbelt, or Telegram delivery. These remain
explicit pre-enablement proofs.

Disable the merge variable, pause, and reconcile in-flight work before rollback.
Revert maintenance as one unit across locks and keep previous host generations.
Linux self-deploy builds the immutable resolved revision and attempts rollback
after activation/health failures. macOS keeps its activation prompt and needs a
tested previous-generation recovery procedure. CI never activates hosts; build
success does not prove boot, desktop, or application health.
