# ZeroClaw household assistant (thorny)

Thorny runs one ZeroClaw daemon, `zeroclaw-home.service`, from the maintained
fork at `github:averagechris/zeroclaw` (flake input `zeroclaw` in
`flakes/hosts/thorny/flake.nix`). One Telegram bot serves the owner, invited friends with private memory, and
approved groups with one shared memory per group.

The host builds the agent runtime, Telegram channel, and schema commands only.
Other channel integrations are excluded from this service package.
The generated configuration explicitly sets `schema_version = 3`; leaving it
unset invokes legacy migration and loses the aliased provider and Telegram
settings. The default is `gpt-6-luna` with medium reasoning. `/model` also
offers `gpt-6.1-sol` and `gpt-6-astra`; each passed a live account check.
Automatic acknowledgment reactions are disabled; typing indicates that Michi
is working on a reply. The model can choose a contextual reaction, which the
runtime confines to the current channel and conversation.

When the agenix ciphertext is absent, ZeroClaw's CLI is available for setup, but there is no
`zeroclaw-home` service, user/state declaration, or age secret until the tracked
`secrets/thorny/zeroclaw-env.age` file exists. Do not deploy the enabled service
until that ciphertext has been created and reviewed through the normal secret
workflow. The enablement check uses the source path before copying the secret
into the store, so it also works during flake checks with `--no-build`.

- Config: `flakes/hosts/thorny/zeroclaw.nix`
- Personality: `flakes/hosts/thorny/michi/SOUL.md` and `IDENTITY.md`
- Upstream runbook: `docs/project-maps/telegram-assistant/setup.md` in the fork
- State: `/var/lib/zeroclaw-home` (service user `zeroclaw-home`), including
  `.secret_key`, the Codex auth profile, sessions, and memory. Back it up.

## Personality

Michi is a helpful kitten with an evil-mastermind reputation and a small smug
grin. Mischief stays in the wording; the work stays accurate. The soul file
defines the tone, bilingual conversation, contextual reactions, and plain
writing rules, including no em dashes. The identity file defines the character.

The host reads these two Markdown files into the existing inline identity
configuration for the owner, guest template, and group template. Invited agents
inherit that public personality. Their workspaces, history, and memories remain
separate. No personality file contains personal information about the owner or
friends. The owner also gets `OWNER_TOOLS.md` with shell and video delivery
instructions. Guests and groups do not inherit those instructions. Edit the
source files and redeploy to change the voice reproducibly.

## Secret and owner identity

Create the bot with [@BotFather](https://t.me/BotFather). Keep
`/setjoingroups` **Enable** so it can join groups. Set `/setprivacy` to
**Disable** before adding it if ordinary group messages should reach it.
If already added, remove and re-add it after changing privacy mode.

The encrypted `secrets/thorny/zeroclaw-env.age` file contains:

```sh
BOT_TOKEN=<complete integer:random-token string from BotFather>
TG_OWNER_ID=<positive owner user ID>
KAGI_API_KEY=<Kagi Search and Extract API key>
OPENCODE_GO_API_KEY=<OpenCode Go API key for voice transcription>
GH_TOKEN=<GitHub token limited to selected personal repositories>
```

Provision or edit it from the repo's `secrets/` directory:

```sh
mkdir -p secrets/thorny
cd secrets
direnv exec .. agenix -e thorny/zeroclaw-env.age
```

Track the ciphertext for pure flake evaluation. Never put the plaintext token
in Git or paste it into chat. Kagi search and page extraction use
`KAGI_API_KEY`. Voice transcription uses the OpenCode Go subscription through
`OPENCODE_GO_API_KEY`. Image generation and editing reuse the existing Codex
login and its included usage. `OPENAI_API_KEY` can remain in the secret, but
the active configuration does not use it. OpenRouter is not configured for
automatic fallback.

Only the owner needs a preconfigured Telegram ID. Keep it in the encrypted
secret alongside the token so the host configuration remains reproducible
without exposing the ID in this public repository. The module substitutes
both placeholders into the service's private `config.toml`. A missing or
malformed owner ID denies routing and invitation controls.

Collect the owner ID from Telegram's `getUpdates` while the daemon is stopped:
press Start and send the bot a DM, then read `message.from.id`. Friends and
groups do not need IDs collected or stored in configuration.

## Invite friends and activate groups

After deployment and Codex login:

1. DM `/invite @their_handle` from the configured owner account. Send the
   returned link to that person. Their handle is preapproved for 24 hours;
   opening the link and pressing Start claims the approval for their current
   numeric Telegram ID. Later handle changes do not transfer access.
   For someone without a handle, use `/invite` for a single-use private link
   that also expires in 24 hours.
2. The friend opens it and presses Start. Their subsequent conversation has
   its own private memory, separate from yours and every other friend.
3. Add the bot to a group, then send `/activate@your_bot` there from your owner
   account. Everyone in that group can interact; its memory stays separate
   from private chats and other groups.
4. DM `/guests` to list active chat IDs and pending handles. Use
   `/revoke @their_handle` to cancel an unused approval, or `/revoke <chat-id>`
   to remove enrolled access. Revocation preserves memory; re-enrollment
   restores the same chat's identity. A turn already running may finish.

These commands use
[the fork's Telegram invitations](https://github.com/averagechris/zeroclaw/pull/7)
and [handle approvals](https://github.com/averagechris/zeroclaw/pull/26), both
included in the pinned revision. Older revisions may lack these commands.
Enrollment survives restarts and Nix rebuilds in
`/var/lib/zeroclaw-home/data/telegram-memberships/home.sqlite3`. Back up the entire
state directory. Keep the channel alias `home` stable. Converting a group to a
supergroup creates a new ID; activate it again to start its new memory.

## Codex login

Thorny will use its own ChatGPT/Codex account, separate from work. The current
login stays active until that account is ready. Use the same service-user login
flow to replace it; do not copy workstation credentials or work sessions.

The agents use the ChatGPT/Codex subscription. Log in once as the service
user, after the first deploy:

```sh
sudo -u zeroclaw-home env ZEROCLAW_CONFIG_DIR=/var/lib/zeroclaw-home \
  zeroclaw auth login --model-provider openai-codex --device-code
sudo -u zeroclaw-home env ZEROCLAW_CONFIG_DIR=/var/lib/zeroclaw-home \
  zeroclaw auth status
sudo systemctl restart zeroclaw-home
```

`zeroclaw` on thorny's `PATH` is the same build as the unit.

If device-code login is unavailable, the CLI falls back to browser login.
Before starting login, keep this command running in a separate laptop terminal:

```sh
ssh-lan thorny -N -L 1455:127.0.0.1:1455
```

Open the printed authorization URL locally. The forward carries its callback
back to Thorny; the CLI waits three minutes. If it times out, use the printed
`auth paste-redirect` command as the service user with the same config directory,
and paste the callback URL only into that secure terminal prompt. Keep callback
URLs out of chat and issue reports. Confirm `auth status`, restart the service,
and close the forwarding terminal after login succeeds.

After the first enabled deploy, Codex login remains a manual step as shown
above; provisioning the ciphertext alone does not create the service user's
auth profile. Restart the service after login so the daemon picks up the
service user's saved profile.

## Capabilities

Owner chats, invited friends, and approved groups can use Kagi search and
single-page extraction. Search uses Kagi's default results unless a request
specifies a lens. Extraction accepts one public HTTPS page per call. Search
failures do not silently switch providers.

Sent photos are passed to the chat's model for vision and saved in that chat's
workspace for later edits. Local image references from messages, history, or
tool results can only load files inside that chat's workspace. Telegram reply
attachments use the same workspace boundary. Voice memos are transcribed with
OpenCode Go's `mimo-v2.6-flash`, with reasoning disabled, before the model
responds. Admission and routing happen before any media download,
transcription, or workspace write. If transcription
fails, Michi asks for text rather than guessing what was said.

Short videos are inspected using up to four frames spread across the clip,
plus a transcript when an audio track is present. Clips must be at most 20 MiB
and 120 seconds. Frames fit within 640 by 640 pixels. MP4, MOV, MKV, and WebM
containers are supported. Video members of an album remain context-only;
send a video separately when you want Michi to inspect it. Accepted clips and
extracted frames stay in that chat's workspace for follow-up edits. Each frame includes its saved
path in the model's text context, so Michi can pass it to `image_gen` as a
reference when making a meme or editing a still from the clip. Editing or
exporting a video clip is available through the owner DM's shell tool.

`image_gen` creates and edits images through the existing Codex login using
`gpt-image-2`. Each call returns one image; references must be in the current
chat's workspace. Editing accepts up to four PNG, JPEG, or WebP images totaling
20 MiB, and generated images are limited to 20 MiB. The model can choose a
transparent background for stickers or cutouts. Files remain available for
follow-up edits.

Telegram location pins supply coordinates and optional accuracy to the model.
Venue shares also include the place name and address. Replies to a pin retain
that location in the quoted context. An initial live location is a snapshot;
later movement updates are not consumed.

## Owner shell, browser, and GitHub

Only the owner DM has `shell`. Invited DMs and groups exclude it, including
when the owner speaks in a group. Ordinary permitted commands run without an
approval prompt. Workspace checks, forbidden paths, high-risk command blocking,
and the service's existing systemd sandbox remain enabled. Shell subprocesses
receive `GH_TOKEN` and three fixed Git configuration variables only for the
owner profile. They configure `gh auth git-credential` for
`https://github.com` only, using the token from agenix; other hosts and provider
keys remain excluded. The same GitHub-only helper is available to the owner
service, Codex worker, phone host, and direct `codex` CLI. The worker passes
these three settings to Codex child processes through its environment allowlist.
No workstation login or credential file is copied.
GitHub recommends a fine-grained token restricted to selected repositories and
needed permissions. See [token setup](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens).
GitHub CLI uses [GH_TOKEN](https://cli.github.com/manual/gh_help_environment)
without a copied workstation login. Git uses the scoped helper to ask `gh` for
credentials when a GitHub HTTPS operation needs them. Token scope controls which
operations work.

The service PATH includes `gh`, `jj`, `git`, `rg`, `jq`, `fd`, and `curl`.
Use an explicit GitHub repository, especially from jj workspaces. Repository
clones and edited files belong inside the owner's workspace. Authenticated
GitHub HTTPS operations use the managed helper automatically. No `~/.gitconfig`
changes, work credentials, or workstation sessions are imported.

`rdny` controls a private headless Chromium browser through an authenticated Unix
broker. Its wrapper fixes the browser executable, ffmpeg executable, home, and
state directory to the owner workspace. Browser lifecycle is managed by
`michi-browser.service`; normal navigation and inspection use the existing
session. Do not start, stop, or attach a separate browser from the bot. Screenshots
can be returned with `[IMAGE:/absolute/path.png]` inside the owner's workspace.

Chromium runs in a separate service because it needs namespace creation and
JavaScript JIT, which the bot unit denies. The browser unit retains Chromium's
sandbox, private devices and temporary files, no new privileges, a read-only
system, and owner-workspace-only writes. It receives no agenix environment file.
The browser joins the bot's user namespace through a root-owned runtime link,
so rdny can verify the broker's process identity. It starts after the bot and
restarts with it. A small privileged lifecycle helper publishes only that link;
it does not expose a general privileged command. The bot unit's existing
protections remain unchanged. Neither service controls
an interactive desktop or an everyday browser profile.

FFmpeg and ffprobe are available for trimming, cropping, captions, and GIFs.
Michi can use the saved source clip rather than asking for a still image.
Edited files stay inside the owner's workspace and are returned using Telegram's
video or document attachment markers. This does not add a paid video
service or access to the desktop session.

## Memo trial

`memo` replaces the built-in durable memory tools. The native backend is `none`,
auto-save is off, and hygiene is off. Existing SQLite files remain untouched for
rollback, but the trial starts with empty memo stores. Conversation history,
Codex authentication, and invitation memberships are separate from durable
memory and remain intact.

Each routed agent uses its own workspace's `memo` directory with the explicit
`default` store. Telegram invitation routing assigns a separate agent to each
invited DM and approved group. The tool accepts no store or filesystem selector,
so a model cannot choose another chat's memory.

Memo keeps append-only notes of at most 280 UTF-8 bytes on one line. Michi reads
a `wake` of up to 256 lines at the start of a turn and records lasting facts with
`note`. It supplies faithful summaries with `nap` when memo requests them. Complete
a pending summary before retrying an incomplete wake. Memo does not perform
keyword search or delete individual notes. Correct a fact with a new note;
reset a store from the host when needed. Do not write secrets into memory.
Both risk profiles allow 524,288 characters per tool result so the full wake
survives runtime result trimming, including JSON escaping. Individual tools
retain their own output limits; memo's CLI output stays capped at 512 KiB.

The shared soul prompt tells Michi to save useful preferences, personal
background, recurring needs, and ongoing plans proactively. Routine saves and
summary work stay out of its replies. It preserves uncertainty, avoids guesses
and duplicates, and asks only when ambiguity would materially misrepresent
someone. An explicit request to inspect memory gets a plain answer; a failed
explicit save gets reported.

To inspect a store, run the pinned memo executable as `zeroclaw-home` with
`--data-dir <agent workspace>/memo --store default -o json wake --lines 256`.
An incomplete wake exits with a structured pending range; Michi completes that
workflow through its tool. Avoid adding test notes to a real store.

To reset one store, stop `zeroclaw-home`, move that agent's `memo` directory
aside, and start the service again. To roll back the trial, restore the prior
host revision and deploy it. Its native memory files remain available. Memo
notes are not imported into the prior backend.

Cross-chat memory sharing is outside this trial.

## Follow-up

Keep Kagi on its default search for now. Revisit lenses with Chris: explain how
they filter results, then help create lenses for his recurring searches.

Use rdny for browser automation and shell for other owner host work. Native desktop control and a richer
Codex task interface are deferred. Keep Thorny's separate
ChatGPT/Codex account and browser profile independent of work. Linear, Granola,
and Slack are not part of the personal assistant. Consider ctx only for Michi's
own coding history, and sideshow if slide creation becomes useful.

## Codex coding jobs

Owner coding requests go through `michi-codex`, backed by Thorny's host-scoped
OpenAI Codex CLI `0.160.0` package. It uses the official
`x86_64-unknown-linux-musl` release archive, including its code-mode host and
bundled resources. Invited DMs and groups have no access to this command. Michi submits
a task, waits for its result, and summarizes the actual change and checks.
The coding fallback is latest Sol at low reasoning, currently Sol 6.1.
Michi chooses Luna medium for mechanical work, Luna high for modest complexity,
and higher Sol reasoning for difficult planning, diagnosis, or review. Astra is
reserved for rare, very complex tasks where Sol at high reasoning leaves
consequential uncertainty unresolved. `submit --model luna --reasoning high`
selects an explicit pair. Available model choices are `sol`, `luna`, and `astra`;
reasoning can be `low`, `medium`, `high`, `xhigh`, `max`, or `ultra`. Luna does not
support `ultra`. Without an explicit effort, Sol and Astra use low, and Luna uses
medium. Job status reports the actual model and effort. Michi's conversation
default remains Luna medium.

Nix installs the shared working-style guidance and Michi's coding policy into
the dedicated profile's `.codex/AGENTS.md`. Codex follows each project's own
instructions too. Clear, independent implementation can use Luna subagents,
which default to medium reasoning. Escalation carries the failed check and
unresolved question back to Sol. A follow-up uses an explicit job ID with
`--resume`, never the latest session from an unrelated request.

This is a temporary host-scoped pin because Nixpkgs Codex `0.154.0` rejects
the live account's `gpt-6-luna` model. The archive SHA-256 is
`4fcc47ab57f52ff75363951a8761146cd10c8288bd86fed45487dbb204a16b71`.
Remove the package and restore `pkgs.codex` in the Thorny module once Nixpkgs
provides `0.160.0` or newer and the live account accepts the configured models.

The command writes private requests and results below the owner workspace's
`.codex-jobs`. A systemd path unit starts `michi-codex-worker.service` when requests
arrive. The worker processes them sequentially, outside the bot shell's
60-second deadline. `status`, `wait`, `result`, and `cancel` take a job ID.
Results remain on disk when a Telegram reply truncates them. `wait` defaults to
10 seconds and accepts at most 20. `result` displays up to 12,000 characters
and reports the full result path. A job has a two-hour runtime limit. A worker restart
interrupts active work; it does not silently restart the coding task.

Michi submits coding requests with `submit --notify-owner`. This opts that
specific job into a durable follow-up to the configured owner's private DM.
The owner shell receives `TG_OWNER_ID` to record the originating DM at
submission. Delivery must match that saved ID to the current encrypted
`TG_OWNER_ID`; it refuses to reroute old jobs if the owner configuration changes.
Requests cannot choose another chat. Phone sessions, ordinary CLI jobs, and jobs
created before this feature remain quiet. Resumed jobs opt in separately.
Neither guests nor groups receive the submit command, including when the owner
speaks in a group.

`michi-codex-notify.service` checks opted-in jobs every 30 seconds through a
systemd timer. It makes no model calls and never restarts coding work. It sends
one bounded plain-text message with the terminal status, job ID, and Codex's
final account of changes, checks, and unresolved issues. Full results remain on
disk. A successful Codex exit is not proof that the requested work succeeded;
opted-in prompts ask for an explicit outcome, including `needs_input` when
blocked. Cancellation and interrupted work also receive follow-ups. Session
IDs are saved during execution so interruption does not lose the association.

Private per-job delivery records survive service restarts. Acknowledged
deliveries are not repeated. Transient network, server, and rate-limit failures
retry with bounded backoff; permanent Telegram rejection stops retrying. If
Telegram accepted a message but its response was lost, retry can produce a
duplicate. Telegram's send API has no idempotency key, so exactly-once delivery
is not promised. No receipt placeholders or periodic progress messages are sent.

Only the delivery service receives `BOT_TOKEN` and `TG_OWNER_ID`, extracted by a
root pre-start helper into a private temporary environment file. That file is
removed on stop. The coding worker still receives only its existing GitHub
credential. Delivery retains the owner workspace mount and service restrictions
and cannot read guest workspaces. Inspect failures through per-job delivery
records without printing credentials or raw HTTP errors.

Check this feature with `python3 -m unittest discover -s tests -p
'test_michi_codex*.py'` inside the project environment, or build
`.#checks.x86_64-linux.michi-codex`. Tests use temporary job stores and fake
Codex/Telegram endpoints, including restart and delivery failure cases. They do
not write memo notes or remove saved sessions. Roll back by reverting the
follow-up change and redeploying; job results and session history remain intact.

The worker exposes only the owner workspace from the shared bot state tree.
Other agents' state and the bot configuration are hidden. It retains filesystem,
home, device, user, and privilege restrictions. It permits namespaces and JIT
needed by Codex and coding tools, while the bot service keeps its original
restrictions. The worker leaves `ProcSubset`, `ProtectKernelTunables`, and
`ProtectKernelLogs` unset because their process-filesystem restrictions prevent
bubblewrap from mounting its own `/proc`. The worker has no host capabilities;
the bot retains these settings. The worker permits `AF_NETLINK` so bubblewrap
can set up loopback in the patch tool's offline sandbox. A live patch-only probe
verified that this fixes patch writes without a shell fallback.
Codex runs with its native workspace-write sandbox, network
access for repository work, and no interactive approval prompts. The worker
forwards only `GH_TOKEN` among the provider credentials in agenix.

Codex has separate authentication under the owner's `.codex` directory. It does
not import the existing ZeroClaw login or workstation credentials. After
installation, sign in to Thorny's separate ChatGPT account from SSH:

```sh
sudo -u zeroclaw-home env \
  HOME=/var/lib/zeroclaw-home/agents/owner/workspace \
  CODEX_HOME=/var/lib/zeroclaw-home/agents/owner/workspace/.codex \
  /run/current-system/sw/bin/codex -c cli_auth_credentials_store='"file"' login --device-auth
```

Use the displayed URL and code yourself. Check `michi-codex auth-status` as the
service user afterward. The [official authentication guide](https://learn.chatgpt.com/docs/auth)
describes headless login. [Non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode)
describes execution, JSON events, and explicit session resumption.

The worker PATH includes GitHub and repository tools, Node.js, Python, Nix, and direnv.
Codex uses non-login shells so profile startup cannot replace that PATH.
Use each project's declared development environment for its other dependencies.
No API-key fallback or work account integration is configured.

Check the worker and queue watcher with `systemctl status michi-codex-worker
michi-codex.path`. Use `journalctl -u michi-codex-worker` for startup errors;
Codex events and its final message stay in the private job directory. Run the
offline job-control checks with `nix build .#checks.x86_64-linux.michi-codex`.
These checks are also part of the CI coverage tier.


The owner DM also exposes `codex`, with HOME and CODEX_HOME fixed to the dedicated
profile. `michi-codex-sessions list --limit 20` lists sessions from the phone host;
`show SESSION_ID` reads status and recent turns. These queries do not call a
model. Session inspection uses the private local app-server connection. Invited
DMs and groups retain their shell exclusion and have no Codex command grant.

## Phone access

`michi-codex-remote.service` runs the pinned CLI's foreground remote-control
host at boot after the dedicated account has logged in. The owner paired an
iPhone successfully through CLI 0.160.0. ChatGPT required MFA on that account
before host registration. The service uses the same owner workspace, account,
coding guidance, tools, and filesystem restrictions as the coding worker.
It forwards only `GH_TOKEN` from agenix, using a separate runtime credential
file so worker cleanup cannot remove the host's credentials.

Phone tasks default to Sol 6.1 low, with Luna medium as the subagent default.
The phone can choose a different model or reasoning effort for a task.
The foreground app server bypasses the managed daemon's separate auto-updater;
Nix controls the installed CLI. Restarting it reuses the profile's enrollment.
The app server reconnected with the paired daemon's host identity.
Its local socket lives in a private runtime directory shared with the owner
client. This avoids the CLI's hashed socket alias being hidden in PrivateTmp.
The resolved Unix socket path stays below Linux's length limit.

Check it with `systemctl status michi-codex-remote` and
`journalctl -u michi-codex-remote`. Stop it with
`sudo systemctl stop michi-codex-remote` to disable phone access until the next
start. Systemd sends SIGINT for the CLI's shutdown handler. The bot and coding
queue run independently.

For a new phone, stop the foreground service before using the CLI's managed
pairing flow. Run these commands from SSH under the dedicated profile:

```sh
sudo systemctl stop michi-codex-remote
sudo -u zeroclaw-home env \
  HOME=/var/lib/zeroclaw-home/agents/owner/workspace \
  CODEX_HOME=/var/lib/zeroclaw-home/agents/owner/workspace/.codex \
  PATH=/run/current-system/sw/bin \
  sh -c 'codex remote-control start --json && codex remote-control pair --json'
```

Enter the short-lived manual code on the phone, signed into the same account
and workspace. After pairing, stop the managed daemon under the same profile
with `codex remote-control stop --json`, then restart the foreground service.
Do not run both hosts together. The [official CLI commands](https://learn.chatgpt.com/docs/developer-commands#codex-remote-control)
describe the experimental pairing commands. The [Remote guide](https://learn.chatgpt.com/docs/remote-connections)
still documents desktop hosts on Mac and Windows; this Linux CLI route is a
verified experimental setup, without a Linux desktop app or desktop computer
control. Browser work continues through rdny.

## Operations

```sh
systemctl status zeroclaw-home
journalctl -u zeroclaw-home -f
```

The daemon boots even when config validation fails and only logs
`config has validation errors`. Look for that and for
`invalid Telegram route table`, which means the bot answers nobody. Owner routing and templates are read at startup, so restart after changing
those or the secret. Invitations and group approvals apply immediately.

To update the fork, first set the merged revision in
`flakes/hosts/thorny/flake.nix`. Run
`nix flake update zeroclaw --flake ./flakes/hosts/thorny`, then
`nix flake update thorny` at the root. Keep the source URL and both lock files
on the same revision.
