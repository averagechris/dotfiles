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
friends. Edit the source files and redeploy to change the voice reproducibly.

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

1. DM `/invite` to the bot from the configured owner account. Send the returned
   link to one friend. It expires in 24 hours and can be used once.
2. The friend opens it and presses Start. Their subsequent conversation has
   its own private memory, separate from yours and every other friend.
3. Add the bot to a group, then send `/activate@your_bot` there from your owner
   account. Everyone in that group can interact; its memory stays separate
   from private chats and other groups.
4. DM `/guests` to list active chat IDs, and `/revoke <chat-id>` to remove
   access. Revocation preserves memory; re-enrollment restores the same
   chat's identity. A turn already running may finish.

These commands require
[the fork's Telegram invitations change](https://github.com/averagechris/zeroclaw/pull/7),
which is included in the pinned revision. Updating to a revision before that
change would disable invitation routing.
Enrollment survives restarts and Nix rebuilds in
`/var/lib/zeroclaw-home/telegram-memberships/home.sqlite3`. Back up the entire
state directory. Keep the channel alias `home` stable. Converting a group to a
supergroup creates a new ID; activate it again to start its new memory.

## Codex login

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
send a video separately when you want Michi to inspect it. Temporary source
files are removed after processing; retained frames stay in that chat's
workspace for follow-up questions or image edits. Michi can make a still meme
from a video frame. Editing or exporting a video clip needs a separate tool.

`image_gen` creates and edits images through the existing Codex login using
`gpt-image-2`. Each call returns one image; references must be in the current
chat's workspace. Editing accepts up to four PNG, JPEG, or WebP images totaling
20 MiB, and generated images are limited to 20 MiB. The model can choose a
transparent background for stickers or cutouts. Files remain available for
follow-up edits.

Host shell access remains unconfigured.

## Follow-up

Add video editing after choosing the first supported operation with Chris.
Start with a short clip to check the output and processing cost.

Keep Kagi on its default search for now. Revisit lenses with Chris: explain how
they filter results, then help create lenses for his recurring searches.

Install the ChatGPT desktop app on Thorny and sign in with Chris's ChatGPT
subscription. Then connect Michi to Codex and remote computer use. Check Linux
support, the desktop session, and authentication first; design permissions for
owner access while preserving invited friends' and groups' isolation.

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
