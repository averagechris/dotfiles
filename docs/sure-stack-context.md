# Sure Stack Context Skill

`suremac` installs a host-specific OpenCode skill named `sure-stack-context` for
debugging Sure deployed environments across Datadog, Sentry, and Kubernetes.

The public skill lives at
`flakes/hm-modules/modules/opencode/skills/sure-stack-context/SKILL.md`. It is a
concise incident-debugging router for `sentry`, `pup`, and `kubectl`, including
context inference, shard-to-namespace discovery, service/worker/cronjob
inspection, read-only defaults, and bounded output.

## Private appendix

Sure-specific service, ecosystem, and environment hints are intentionally not
stored in plaintext because this repo is public. `suremac` decrypts
`secrets/opencode-sure-stack-context.age` with agenix and appends it to the local
installed copy of the `sure-stack-context` skill during Home Manager activation:

```text
~/.config/opencode/skills/sure-stack-context/SKILL.md
```

Keep the public skill generic enough to be safe for the repo. Put private or
company-specific context in the encrypted appendix.

## suremac tools

`suremac` installs and exposes these related tools to OpenCode agents:

- `pup` - Datadog CLI
- `sentry` - Sentry CLI
- `kubectl` - Kubernetes CLI

The tools are available both in Chris's Home Manager `home.packages` and in the
OpenCode runtime note via `dotfiles.opencode.agentTools`.

## Maintenance

When changing private Sure stack context:

```bash
cd ~/dotfiles/secrets
agenix -e opencode-sure-stack-context.age
```

Do not copy decrypted content into public docs, AGENTS.md, skill files, or chat
summaries. Summarize changes at the level of “updated private stack context” when
needed.
