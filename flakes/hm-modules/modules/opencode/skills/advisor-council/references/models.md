# Council roster

Use native Codex delegation for the OpenAI seats when the requested selection is available. Use the model IDs below with the requested effort in OpenCode. The public IDs do not guarantee runtime access.

| Advisor | Selection | Lens |
| --- | --- | --- |
| **Claude Opus 5.5** | `openrouter/anthropic/claude-opus-5.5#high` | Default panel seat. Independent code and design review. |
| **GPT-6.2 Sol** | Codex `gpt-6.2-sol`, high | Default panel seat. Practical implementation, validation, and tradeoffs. |
| **GPT-6.2 Astra** | Codex `gpt-6.2-astra`, high | Deep architecture, correctness, and failure modes. |
| **Claude Fable 5.2** | `openrouter/anthropic/claude-fable-5.2#high` | Open-ended design, simplicity and taste. Check [provider retention terms](https://openrouter.ai/anthropic/claude-fable-5.2) before including work material. |
| **Gemini 4 Carbon** | `openrouter/google/gemini-4-carbon#high` | Default panel seat. Defensive security and complex reasoning. |
| **Gemini 4 Neon** | `openrouter/google/gemini-4-neon`, effort from live catalog | Trial for an alternative perspective. Verify this entry and variant before using it. |
| **Daybreak Blue** | Codex CLI `gpt-6-sol`, high | Optional defensive review of approved evidence. |

## Daybreak Blue from OpenCode

For defensive reviews, OpenCode can call Codex CLI through the bundled
`scripts/review-daybreak.sh`. Prepare the review question and approved excerpts
as text on standard input. Use it for threat modeling, security findings,
remediation, and defensive regression checks.

```sh
bash scripts/review-daybreak.sh --login
bash scripts/review-daybreak.sh < approved-review.txt
```

This seat needs Codex CLI 0.163.0 or later, `jq`, and an account with Daybreak
access. The one-time sign-in stores the advisor's login in a dedicated Codex
home under `${XDG_STATE_HOME:-$HOME/.local/state}/opencode/daybreak-codex`.
Reserve that directory for the advisor. Each review requests Daybreak Blue
in an ephemeral read-only session. Shell
tools, web search, agents, apps, plugins, and hooks are disabled. OpenCode owns
implementation and verification. Record the seat as unavailable if the account
or CLI rejects it.
[Daybreak CLI guide](https://help.openai.com/en/articles/20001607-using-daybreak-in-codex-cli)

The runner selects `daybreak_blue` with `gpt-6-sol`. Availability varies by
account, model, and CLI version. Run `command -v codex`, `codex --version`,
and `codex exec --help` in the executor that will run the review. The installed
CLI may expose additional programs. Check eligibility for the selected model
and account using the Daybreak guide above.

## External reviews

Check the endpoint's terms and the task's data policy before sharing approved material. Use the bundled runner from this skill's directory, or resolve its path relative to this file. It needs Bash, jq, and OpenCode 2.x. It runs OpenCode with tools denied in a clean home and scratch directory, using `OPENROUTER_API_KEY` or the host's readable agenix OpenRouter key. On a new executor or CLI version, verify tool denial with a harmless file-read test before sharing work.

```sh
bash scripts/review.sh 'openrouter/google/gemini-4-carbon#high' \
  'Review the attached material independently. Give consequential findings with reasons.' \
  /path/to/approved-excerpt.diff
```

Use the same command with the roster selection for other OpenRouter seats. Put small approved excerpts in the prompt or pass larger ones as file arguments. The runner supplies the explicit reasoning variant when the local catalog is stale. Verify trial selections such as Neon against the current catalog first.

Launch the runner in a managed background process and keep its process handle.
Use short tool yields and poll the same process while the other seats work.
Avoid wrapper timeouts unless the task has a deadline. High-effort reviews can
take several minutes without new output, so let quiet seats finish after other
reviews return. The runner reports status on stderr and the completed review on
stdout. Use the process exit to confirm the outcome. Retry a transient failure
once with the same model, effort, and routing when useful. If a task deadline
ends the wait, report the seat as interrupted and say which deadline applied.

Normal routing inherits OpenRouter's account and key policies. Pass `--zdr` or `--deny-data-collection` before the model when the material requires those restrictions. The two controls are independent. Carbon can be reachable under normal routing and have no eligible endpoint under `--zdr`. If a required filter blocks a seat, report it as unavailable without retrying under looser restrictions.

Cloud and Dot sessions need their own executor, CLI, and provider access. A Dot shared install may be at `/workspace/shared/cloud-tools/bin/opencode`. An authentication error from the runner means the selected key needs attention. Saved OpenCode credentials are outside the isolated session. Report blocked seats without substituting. For Daybreak, record the model and tier.
