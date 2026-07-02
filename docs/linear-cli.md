# Linear CLI

The `dotfiles.linearCli` Home Manager module installs the `linear` CLI from the
`linear-cli` flake input and manages its non-secret context configuration for
agents.

## What the module manages

- Installs the configured Linear CLI package.
- Installs static bash, fish, and zsh completions when
  `dotfiles.linearCli.completions.enable = true`.
- Merges `dotfiles.linearCli.context` into
  `~/.config/linear-cli/config.toml` during Home Manager activation.
- Optionally runs a periodic `linear context refresh` launchd job on Darwin.

The activation merge intentionally preserves authentication/profile metadata in
the existing CLI config file. Credentials remain in the OS keyring via
`linear auth login`; the module only writes non-secret context and policy hints.

## suremac defaults

`suremac` enables the module with the `inputs.linear-cli` package and configures
agent-facing Sure EPD conventions:

- Default team: `EPD`
- Default new-work status: `Backlog`; when the user clearly intends to work the
  issue immediately, agents may assign it to `me` and set status to
  `In Progress`
- Required label groups: exactly one `domain` and exactly one `type`
- Execution label default: `agentic`
- Optional suggestion groups: `lob` and `carrier`
- Fibonacci estimation rubric: `0, 1, 2, 3, 5, 8`
- Estimate and assignee required before cycle work
- Project/initiative discovery should fetch options and ask when ambiguous
- Daily background refresh of labels, projects, initiatives, statuses, and teams

These defaults are deliberately high-level. The module does not embed private
member mappings, repo ownership, or complete domain taxonomies; agents should use
`linear context options ... --output json --compact` to fetch current options
from Linear.

The Linear CLI invalidates some affected caches after mutations such as project
or label changes, but invalidation is not the same as repopulating the cache. If
an agent creates a project and needs it to appear in option discovery during the
same session, it should refresh the relevant resource explicitly:

```bash
linear context refresh projects --quiet --retry 3
```

The daily launchd job keeps the normal steady-state cache warm:

```nix
dotfiles.linearCli.cacheRefresh = {
  enable = true;
  intervalSeconds = 86400;
  resources = ["labels" "projects" "initiatives" "statuses" "teams"];
};
```

Logs are written to `~/Library/Logs/linear-cli-context-refresh.log`.

## Override pattern

Host or user configs can override the generated context:

```nix
dotfiles.linearCli = {
  enable = true;
  package = inputs.linear-cli.packages.${pkgs.stdenv.hostPlatform.system}.linear;

  context.defaults.status = "Triage";
  context.agent_instructions = [
    "Fetch current Linear options and ask before choosing ambiguous labels."
  ];
};
```

Repository-local `.linear.toml` files still take precedence at runtime because
the CLI merges user context with project context when `linear context` runs.

## Useful commands

```bash
linear auth login
linear config show
linear context --output json --compact
linear context options labels --group domain --output json --compact
linear context refresh labels projects initiatives statuses teams
linear context refresh projects --quiet --retry 3
linear doctor
```
