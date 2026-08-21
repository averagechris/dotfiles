# Ctx

Ctx is the local agent-history search CLI used by OpenCode agents to look up
prior coding-agent sessions and events.

## suremac setup

`suremac` enables the Home Manager module:

```nix
dotfiles.ctx = {
  enable = true;
  package = inputs.ctx.packages.${pkgs.stdenv.hostPlatform.system}.ctx;
  index.enable = true;
};
```

The module installs `ctx` and creates a frequent background indexing job. On
Darwin this is a `launchd` user agent named `ctx-index` that:

1. refreshes ctx's source catalog with `ctx setup --catalog-only --progress none`
2. imports all discovered histories with `ctx import --all --resume --progress none`

The job runs at load and then every five minutes (`intervalSeconds = 300`). Logs
go to `~/Library/Logs/ctx-index.log`.

## Linux / tater support

The same Home Manager module creates a `systemd --user` oneshot service and timer
on Linux when `dotfiles.ctx.index.enable = true`. The timer uses the same
`intervalSeconds` option and starts one minute after boot. `tater` enables the
same five-minute index refresh via this timer.

## Manual commands

Useful manual checks:

```bash
ctx status
ctx sources
ctx import --all --resume --progress plain
ctx search "query text"
```

Use `ctx import --provider <provider>` or `ctx import --path <path> --provider
<provider>` for targeted one-off imports when debugging a source.

## Agent workflow

Recall and reflection searches stay within the active project unless the user
asks to cross that boundary. Agents set a topic and time range first, inspect
`ctx status`, `ctx sources`, and command help, then run bounded searches by
project, path, symbol, feature, or issue identifier. They read only matching
events and record the query scope plus source, session, and event identifiers
when ctx provides them.

Ctx records historical reports, not current truth. Agents verify important
claims against live files, jj state, tests, pull requests, issues, docs, or
telemetry. An empty search is limited by its query, indexing, and retention and
does not prove that no record exists. Use targeted imports only when a relevant
source is missing or stale, rather than broad imports for every lookup.
