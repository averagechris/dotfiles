# ZeroClaw household assistant (thorny)

Thorny runs one ZeroClaw daemon, `zeroclaw-home.service`, from the maintained
fork at `github:averagechris/zeroclaw` (flake input `zeroclaw` in
`flakes/hosts/thorny/flake.nix`). One Telegram bot serves the owner, invited friends with private memory, and
approved groups with one shared memory per group.

The host builds the agent runtime, Telegram channel, and schema commands only.
Other channel integrations are excluded from this service package.

When the agenix ciphertext is absent, ZeroClaw's CLI is available for setup, but there is no
`zeroclaw-home` service, user/state declaration, or age secret until the tracked
`secrets/thorny/zeroclaw-env.age` file exists. Do not deploy the enabled service
until that ciphertext has been created and reviewed through the normal secret
workflow. The enablement check uses the source path before copying the secret
into the store, so it also works during flake checks with `--no-build`.

- Config: `flakes/hosts/thorny/zeroclaw.nix`
- Upstream runbook: `docs/project-maps/telegram-assistant/setup.md` in the fork
- State: `/var/lib/zeroclaw-home` (service user `zeroclaw-home`), including
  `.secret_key`, the Codex auth profile, sessions, and memory. Back it up.

## Secret and owner identity

Create the bot with [@BotFather](https://t.me/BotFather). Keep
`/setjoingroups` **Enable** so it can join groups. Set `/setprivacy` to
**Disable** before adding it if ordinary group messages should reach it.
If already added, remove and re-add it after changing privacy mode.

The encrypted `secrets/thorny/zeroclaw-env.age` file contains:

```sh
BOT_TOKEN=<complete integer:random-token string from BotFather>
TG_OWNER_ID=<positive owner user ID>
```

Provision or edit it from the repo's `secrets/` directory:

```sh
mkdir -p secrets/thorny
cd secrets
direnv exec .. agenix -e thorny/zeroclaw-env.age
```

Track the ciphertext for pure flake evaluation. Never put the plaintext token
in Git or paste it into chat. Kagi remains disabled; add `KAGI_API_KEY` later
when enabling search.

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

These commands use the revision pinned for
[the fork's Telegram invitations change](https://github.com/averagechris/zeroclaw/pull/7).
Keep that revision until the change is merged; updating to an earlier main
revision would disable invitation routing.
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

## Stages

1. Owner routing, invitations, and isolated memory, with memory tools only.
2. Kagi search: set `kagiEnabled = true` in `zeroclaw.nix` once the stage 1
   checks in the runbook pass. `KAGI_API_KEY` must already be in the secret.
3. Owner shell: not configured. Needs stage 1 to have held up in real use.

## Operations

```sh
systemctl status zeroclaw-home
journalctl -u zeroclaw-home -f
```

The daemon boots even when config validation fails and only logs
`config has validation errors`. Look for that and for
`invalid Telegram route table`, which means the bot answers nobody. Owner routing and templates are read at startup, so restart after changing
those or the secret. Invitations and group approvals apply immediately.

To update the fork: `nix flake update zeroclaw --flake ./flakes/hosts/thorny`,
then `nix flake update thorny` at the root.
