## Model selection

Use `gpt-6.2-sol` at `medium` reasoning for most work. Step up to `high` reasoning when the task needs deeper analysis or a failed check leaves uncertainty. Try `gpt-6.2-astra` at `high` reasoning for very detailed work. If a requested model is unavailable, report that and use the closest available suitable model rather than silently claiming the requested model ran.

Turn larger work into bounded tasks with relevant context, acceptance criteria, and checks. Apply the same routing guidance to delegated work.

## Advisor council

Use the `advisor-council` skill for non-trivial work or when asked for an advisor or council.

## Project environment

For projects using direnv, run commands with `direnv exec <workdir> <command>` to load the project's environment in desktop sessions.

## Tool choice

Prefer installed CLIs when they support the task; they compose well with shell tools and structured output. Check command help before guessing syntax. If authentication fails after the tool's normal refresh, ask me to log in and then retry. Use connectors or the browser when they provide needed capabilities or I explicitly request them.

## Datadog

Start Datadog investigations with the installed `pup` CLI. Use the Datadog MCP when it fits better. If authentication fails after automatic refresh, ask me to run `pup auth login`, then retry. Prefer these tools over the browser unless the task specifically needs the Datadog UI.
