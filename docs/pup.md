# Pup Datadog CLI

`pkgs.pup` packages Datadog's Pup CLI from the official GitHub release
archives. The derivation lives at `flakes/base-lib/packages/pup.nix` and is
exposed through the shared base-lib overlay.

## suremac integration

`suremac` installs `pup` in Chris's Home Manager `home.packages` and exposes it
to OpenCode agents as a host-specific tool named `pup` with the prompt
description `Datadog CLI`. It also installs the repo-managed `pup-cli` OpenCode
skill with compact usage guidance for Datadog queries.

Pup supports OAuth login and Datadog API/app-key environment variables. The
Nix package does not manage credentials; use Pup's own authentication flow or
provide the Datadog environment variables required by the command you run.

```bash
pup auth login
pup auth status
pup monitors list
```

## Agent usage

The `pup-cli` skill is intentionally minimal. Its public guidance keeps Datadog
output bounded and filtered with `--read-only`, `--no-agent`, `--jq`, compact
formats such as `-o csv`, and explicit limits/time windows. `--no-agent` avoids
Pup's `status`/`data`/`metadata` agent envelope when agents only need raw
filtered output, and `--jq` is applied to the response payload before formatting.

Org-specific stack and ecosystem hints are intentionally not stored in plaintext
in this public dotfiles repo. They now live in the separate encrypted
`sure-stack-context` skill appendix, shared by Datadog, Sentry, and Kubernetes
investigations. See [sure-stack-context](/docs/sure-stack-context.md).
For flamegraphs, the public skill tells agents to ask Chris before enabling the
token-heavy Datadog MCP because `pup profiling` does not currently expose
profiler data.

## Updates

`pup` is enrolled in `manual-package-updates.json` as an archive package with an
explicit version requirement. Update it through the manual-package flow so the
version and all platform hashes are changed together:

```bash
update-flakes --manual-packages-only \
  --manual-package pup \
  --manual-version pup=<version>
```

The manifest keeps the normal cooldown enabled. Override it only after reviewing
fresh upstream releases intentionally.
