## Model selection

Budget efficiency matters. Use `gpt-6.1-sol` at `high` reasoning for choosing approaches, planning, and difficult review. Turn the plan into bounded tasks with relevant context, acceptance criteria, and checks. Fan out independent implementation to `gpt-6-luna` when the tasks are clear. Straightforward work can start with Luna directly.

When a task outgrows Luna, bring the failed check and unresolved question back to Sol. Reserve `gpt-6-astra` for rare cases where Sol at high reasoning leaves consequential uncertainty unresolved.

## Taste consultations

Use `opencode run --model <provider/model#variant>` for occasional outside-model feedback. Prefer Fable 5.1 for rare taste consultations; Opus 5.5 is another option. Reach for them when the decision needs judgment about coherence, simplicity, wording, or how an experience feels, and a better choice would justify the expense.

Bring a compact question, candidate approaches, and relevant evidence. Ask for a recommendation with concrete reasons and analysis only, with no edits or delegation. Start with one focused consultation. A follow-up needs a materially revised approach or new evidence. Sol owns the plan and passes clear implementation tasks to Luna.

```sh
opencode run --standalone \
  --model 'openrouter/anthropic/claude-fable-5.1#high' \
  --file /path/to/decision.md \
  'Judge the attached alternatives for coherence and simplicity. Recommend one, explain the tradeoffs, and identify what to cut. Return analysis only; do not edit files or delegate.'
```

## Project environment

For projects using direnv, run commands with `direnv exec <workdir> <command>` to load the project's environment in desktop sessions.

## Tool choice

Prefer installed CLIs when they support the task; they compose well with shell tools and structured output. Check command help before guessing syntax. If authentication fails after the tool's normal refresh, ask me to log in and then retry. Use connectors or the browser when they provide needed capabilities or I explicitly request them.

## Datadog

Start Datadog investigations with the installed `pup` CLI. Use the Datadog MCP when it fits better. If authentication fails after automatic refresh, ask me to run `pup auth login`, then retry. Prefer these tools over the browser unless the task specifically needs the Datadog UI.
