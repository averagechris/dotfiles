# Council roster

Use native Codex delegation for the OpenAI seats when the requested selection is available. Use the model IDs below with the requested effort in OpenCode. The public IDs do not guarantee runtime access.

| Advisor | Selection | Lens |
| --- | --- | --- |
| **Claude Opus 5.5** | `openrouter/anthropic/claude-opus-5.5#high` | Required council seat. Independent code and design judgment. |
| **GPT-6.2 Sol** | Codex `gpt-6.2-sol`, high | Practical implementation, validation, and tradeoffs. |
| **GPT-6.2 Astra** | Codex `gpt-6.2-astra`, high | Deep architecture, correctness, and failure modes. |
| **Claude Fable 5.2** | `openrouter/anthropic/claude-fable-5.2#high` | Open-ended design, simplicity and taste. Check [provider retention terms](https://openrouter.ai/anthropic/claude-fable-5.2) before including work material. |
| **Gemini 4 Carbon** | `openrouter/google/gemini-4-carbon#high` | Defensive security or difficult reasoning. Record a specialized Carbon route separately if explicitly available. |
| **Gemini 4 Neon** | `openrouter/google/gemini-4-neon`, effort from live catalog | Trial for an alternative perspective. Verify this entry and variant before using it. |

## External reviews

Check the endpoint's terms and the task's data policy before sharing approved material. Use the bundled runner from this skill's directory, or resolve its path relative to this file. It needs Bash, jq, and OpenCode 2.x. It runs OpenCode with tools denied in a clean home and scratch directory, using `OPENROUTER_API_KEY` or the host's readable agenix OpenRouter key. On a new executor or CLI version, verify tool denial with a harmless file-read test before sharing work.

```sh
bash scripts/review.sh 'openrouter/google/gemini-4-carbon#high' \
  'Review the attached material independently. Give consequential findings with reasons.' \
  /path/to/approved-excerpt.diff
```

Use the same command with the roster selection for other OpenRouter seats. Put small approved excerpts in the prompt or pass larger ones as file arguments. The runner supplies the explicit reasoning variant when the local catalog is stale. Verify trial selections such as Neon against the current catalog first.

Normal routing inherits OpenRouter's account and key policies. Pass `--zdr` or `--deny-data-collection` before the model when the material requires those restrictions. The two controls are independent. Carbon can be reachable under normal routing and have no eligible endpoint under `--zdr`. If a required filter blocks a seat, report it as unavailable without retrying under looser restrictions.

Cloud and Dot sessions need their own executor, CLI, and provider access. A Dot shared install may be at `/workspace/shared/cloud-tools/bin/opencode`. An authentication error from the runner means the selected key needs attention. Saved OpenCode credentials are outside the isolated session. Report blocked seats without substituting. For Daybreak, record the model and tier.
