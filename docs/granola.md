# Granola CLI

The `dotfiles.granola` Home Manager module installs `granola`, the Rust CLI for
Granola meeting notes, folders, transcripts, and exports.

## Package source

`suremac` provides the package from the upstream GitHub flake:

```nix
inputs.granola-cli.url = "github:averagechris/granola-cli";
```

The module defaults `dotfiles.granola.package` to
`inputs.granola-cli.packages.${system}.default` when that input is available.
Hosts that do not provide the input can leave the module disabled or set
`dotfiles.granola.package` explicitly.

By default, the module also builds shell completions with:

```bash
granola completions bash
granola completions fish
granola completions zsh
```

The generated files are installed into the standard Home Manager profile
completion directories, so Home Manager-enabled Bash, Fish, and Zsh shells can
load the completion for whichever shell is active. Set
`dotfiles.granola.completions.enable = false` to skip installing them.

When bumping the CLI, update both the standalone `suremac` host lock and the
top-level aggregator lock so `nh darwin build ./flakes/hosts/suremac --hostname
suremac` and `nh darwin build . --hostname suremac` resolve the same revision.

## Authentication

Granola credentials are stored by the CLI in the OS keyring (`granola-cli` /
`default`). Plaintext credential config is intentionally not managed.

On `suremac`, the API token is checked in as `secrets/granola-token.age`,
decrypted by agenix to `/run/agenix/granola-token`, and used only during Home
Manager activation. If `granola auth status --output json --compact` reports no
configured key, activation runs:

```bash
granola auth login --key-stdin --validate --quiet < /run/agenix/granola-token
```

Existing keyring credentials are left alone, so rotating the checked-in token may
require `granola auth logout --force` before the next activation or a manual
`granola auth login --key-stdin --validate`.

## suremac configuration

`suremac` enables the module in Chris's Home Manager configuration and adds
`granola` to `dotfiles.opencode.agentTools`, so OpenCode primary agents see it
in their runtime tool note and get the package in their PATH.

`suremac` installs two repo-managed OpenCode skills:

- `granola-meeting-context` retrieves relevant past meetings with bounded
  searches, minimal context, redaction, and evidence citations. CLI mechanics
  come from `granola agent --output json-compact` and command `--help`.
- `live-meeting-feedback` uses fresh raw transcripts for live interpretation,
  question phrasing, quiet watching, and a final debrief. Start with “Be my
  sounding board for [link]. My goal is [goal]. Watch quietly.” Watching refreshes
  about every 20–30 seconds while the agent is actively running; it does not
  continue after the agent stops. Ask questions directly, say “pause” or “stop”
  to stop watching, and “call ended” for a final read and debrief. Feedback stays
  in the chat unless you explicitly request an external action.

For a meeting still in progress, Granola may not expose **Copy link** yet.
Start the note, stop transcription, choose **Generate notes**, copy the link
at the top right, and resume transcription on the same note. This pauses
Granola transcription; the call can continue. The CLI's public API exposes
notes after a summary and transcript have been generated. Live reads use
`granola notes get LINK --fields transcript --output text --no-cache`; verify
that text grows after recording resumes, since API updates can lag.

`suremac` also enables `dotfiles.granola.sync.enable`, which creates a user
LaunchAgent that runs the following command every hour:

```bash
granola sync --since 12h --all --include-transcript --quiet
```

The job uses launchd's `StartInterval = 3600`, runs as a background, low-I/O
process, and writes logs to `~/Library/Logs/granola-sync.log`. launchd does not
wake a sleeping laptop for this job; it only runs while macOS is awake enough to
service user LaunchAgents. The 12-hour rolling window is enough for the hourly
job to pick up recently completed meetings without repeatedly scanning a large
history, and `--include-transcript` keeps the local FTS cache hydrated for
transcript searches.

Other hosts import the shared Home Manager module set but do not enable
`dotfiles.granola` and do not receive the package or token.
