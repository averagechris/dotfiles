# Codex Cloud tooling

Create a private, reusable [Codex Cloud environment](https://learn.chatgpt.com/docs/environments/cloud-environments)
and include the dotfiles repository. From its checkout, use this as the
environment install command:

```sh
bash scripts/setup-codex-cloud.sh
```

The installer registers the shared `advisor-council` skill at
`~/.agents/skills/advisor-council`, linked to the selected dotfiles checkout.
Keep that checkout in the environment. Add the following to the environment's
startup instructions and use it in task shells before running OpenCode:

```sh
export PATH="$HOME/.local/share/dotfiles-cloud/profile/bin:$PATH"
opencode --version
opencode run --help
```

## Nix and portable install

When a working Nix store is available, the installer builds the Linux
`.#cloud-tools` package from the checked-in lockfile. It includes the flake's
OpenCode, Git, GitHub CLI, jj, ripgrep, jq, direnv, Node.js and pnpm. The output
link is private to this setup. Project-specific dependencies still belong in
each project's own setup.

Without a working store, the installer uses the base image's tools and
installs OpenCode 2.0.26 from the official npm Linux archive, verified against
its recorded SHA-512 digest. The portable path needs Bash, curl, GNU tar and
`sha512sum` on glibc Linux (x86-64 or ARM64). Npm and Node are not needed for
the OpenCode installation itself. If Nix starts a build and it fails, fix that
failure before publishing. To update the portable pin, update the release and
both digests from the official npm package metadata.

No installer changes the host OS or creates `/nix`. Check `nix store info`
in the target environment's setup shell. Whether a managed setup can provision
and retain its own `/nix` still needs a test in that environment. The portable
path works without OS-level provisioning. Published environments use a prepared
filesystem for new tasks, while an existing Dot/shared workspace is a
separate executor with its own tools.

## Provider access

Keep the environment private. For OpenRouter, configure a separately scoped
`OPENROUTER_API_KEY` as a cloud network secret for `openrouter.ai`. Test that
the OpenCode client can use the proxy-substituted value. Allow the package and
catalog domains required by the selected setup, including
`registry.npmjs.org` for the portable install. Add only the necessary Nix
source and cache domains if you use the flake path.

Use a synthetic prompt to confirm that each intended provider and reasoning
variant runs in a fresh task. Only share work packets with authorized
providers.

Save the environment, verify the setup report, and publish when ready. Start
a new task in the published environment to verify the tools, skill and
provider route survived. No credentials belong in the repository or the
prepared files.
