# Sentry (`sentry`) CLI

`pkgs.sentry` packages Sentry's new CLI from the npm `sentry` package. The
derivation lives at `flakes/base-lib/packages/sentry.nix`, uses the bundled
CommonJS distribution from the npm tarball, and wraps it with `nodejs_22` because
upstream requires Node.js 22.15 or newer.
The wrapper sets `SENTRY_CLI_NO_UPDATE_CHECK=1` by default because updates are
managed by Nix, not by `sentry cli upgrade`.

This is intentionally separate from nixpkgs' legacy `sentry-cli` package. The
new CLI installs a `sentry` command and is documented at <https://cli.sentry.dev/>.

## suremac integration

`suremac` installs `sentry` in Chris's Home Manager `home.packages` and exposes
it to OpenCode agents as a host-specific tool named `sentry` with the prompt
description `Sentry CLI`. It also installs the repo-managed `sentry-cli` OpenCode
skill for the `sentry` command so agents prefer dedicated Sentry commands, keep
result sets bounded, and avoid mutations unless explicitly asked. For Sure-specific
incident investigation, agents should pair it with the host-specific
`sure-stack-context` skill, whose private encrypted appendix covers company
service/ecosystem hints shared with Datadog and Kubernetes workflows.

Credentials are not managed by Nix. Authenticate interactively with the CLI and
let it store credentials in its restricted local SQLite database under
`~/.sentry/`:

```bash
sentry auth login
sentry auth status
```

## Module decision

There is not currently a separate Home Manager module for Sentry CLI. The CLI's
useful persistent state is either user-local credential/default data managed by
`sentry auth login` and `sentry cli defaults`, or project-local `.sentryclirc`
files that should live with the projects they describe. For the current
agent-first use case, a packaged binary plus OpenCode tool and skill wiring is
simpler and avoids placing Sentry org/project defaults or tokens in this public
dotfiles repo.

Add a module later if there is a concrete need to manage shared environment
defaults such as `SENTRY_ORG`, `SENTRY_PROJECT`, `SENTRY_HOST`, or a token file
through agenix.

## Agent usage

Useful discovery commands:

```bash
sentry org list
sentry project list <org>
sentry issue list <org>/<project>
sentry issue view <issue-id>
sentry schema --help
```

Agents should prefer dedicated commands before falling back to raw API calls with
`sentry api`. For large investigations, use command-specific filters and limits
or `SENTRY_MAX_PAGINATION_PAGES` to cap pagination.

## Updates

`sentry` is enrolled in `manual-package-updates.json` as an archive package with
an explicit version requirement. Update it through the manual-package flow so the
version and npm tarball hash change together:

```bash
update-flakes --manual-packages-only \
  --manual-package sentry \
  --manual-version sentry=<version>
```

The manifest keeps the normal cooldown enabled. Override it only after reviewing
fresh upstream releases intentionally.
