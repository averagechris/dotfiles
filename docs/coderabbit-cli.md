# CodeRabbit CLI

`pkgs.coderabbit-cli` packages the official CodeRabbit CLI binary for Darwin and
installs it on `suremac` as an OpenCode agent tool. The package lives at
`flakes/base-lib/packages/coderabbit-cli.nix` and is exposed by the shared
base-lib overlay.

## What it is good for

CodeRabbit CLI brings CodeRabbit's AI review loop into a local terminal before a
pull request is opened or while changes are still fresh. It is useful for:

- reviewing uncommitted or committed local changes before pushing;
- getting bug, security, performance, and quality findings with suggested fixes;
- streaming structured JSON findings to coding agents with `--agent`;
- replaying the most recent findings during an agent fix loop; and
- diagnosing auth/repository/connectivity problems with `cr doctor`.

CLI reviews are not identical to PR reviews. The CLI is optimized for immediate
local feedback, while PR reviews have broader collaboration and platform context.

## Authentication and setup

After applying the `suremac` config, authenticate once in an interactive shell:

```bash
cr auth login
```

If multiple CodeRabbit organizations are available, switch the browser-login
default organization with:

```bash
cr auth org
```

Check local health with:

```bash
cr doctor
```

For headless or automation use, CodeRabbit supports agentic API-key auth:

```bash
cr auth login --api-key "cr-..."
```

Do not commit or echo API keys. Prefer secret-backed environment handling for
automation.

## Common commands

`cr` is the short alias for `coderabbit`; both names are installed.

| Command | Purpose |
| --- | --- |
| `cr` / `cr --plain` | Run a plain-text review of local changes |
| `cr --agent` | Run a review with structured JSON output for agents |
| `cr --interactive` | Open the interactive terminal UI |
| `cr review --agent -t uncommitted` | Review only uncommitted changes |
| `cr review --agent -t committed` | Review committed changes only |
| `cr review --agent --base origin/develop` | Compare against an explicit remote base branch |
| `cr review --agent --base-commit <sha>` | Compare against a specific base commit |
| `cr review findings` | Replay locally stored findings from the last review |
| `cr review --show-prompts` | Inspect prompts saved from the last review |
| `cr auth status --agent` | Emit structured auth status |

The CLI must run inside a Git repository. This dotfiles repo uses colocated jj,
which still provides the Git repository CodeRabbit expects. Agents should use
`jj status`, `jj diff`, and other jj commands for VCS inspection and change
management, not Git commands, unless the user explicitly requests Git.

## Agent workflow

For OpenCode agents on `suremac`, the generated runtime note includes `cr
(CodeRabbit AI review CLI)`, and `suremac` configures the repo-managed
`coderabbit-cli` skill with the preferred workflow:

1. inspect the intended review scope with `jj status` / `jj diff --stat`;
2. run `cr review --agent` with the narrowest useful scope, passing an explicit
   remote base such as `--base origin/main` in jj repositories;
3. fix `critical` and `major` findings first;
4. optionally address lower-severity suggestions; and
5. re-run one verification review rather than looping indefinitely.

The package is Nix-managed, so do not use `cr update`. To update the CLI, check
`https://cli.coderabbit.ai/releases/latest/VERSION`, then use the manifest-driven
updater with the reviewed version:

```bash
update-flakes --manual-packages-only \
  --manual-package coderabbit-cli \
  --manual-version coderabbit-cli=<version>
```

The updater changes the version and Darwin archive hashes in
`flakes/base-lib/packages/coderabbit-cli.nix`.
