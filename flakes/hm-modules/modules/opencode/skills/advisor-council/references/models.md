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
| **Muse Wonder Full** | Muse Code only, with an entitled subscription and Contributor mode off | Writing, docs and occasional taste. Check `muse exec --help` and the account's model picker before trying it. |

The API model `muse-wonder-1.0` is [Muse Wonder](https://dev.meta.ai/docs/muse-wonder). It is a different seat from Wonder Full, even at maximum effort. Use it only when requested or agreed.

## External reviews

Check the provider's terms for the material. Confirm a usable executor, CLI, authorized provider, exact model and variant. Check `opencode models --standalone` or the model picker.

Use a scratch directory and a clean environment with only PATH, an isolated HOME, and the intended provider credential. Deny tools and verify the setup with a harmless file-read test before sharing work. Put small diffs inline or attach larger excerpts with `--file`.

```sh
OPENCODE_CONFIG_CONTENT='{"permissions":[{"action":"*","resource":"*","effect":"deny"}]}' \
opencode run --standalone --model 'openrouter/anthropic/claude-opus-5.5#high' \
  'Review this evidence independently. Give consequential findings with reasons: <approved evidence>'
```

Cloud and Dot sessions need their own executor, CLI, and provider access. A Dot shared install may be at `/workspace/shared/cloud-tools/bin/opencode`. Report blocked seats without substituting. For Daybreak, record the model and tier.
