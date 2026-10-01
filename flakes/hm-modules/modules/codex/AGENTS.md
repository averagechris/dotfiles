## Codex workflow

Use native Codex agents, Git worktrees, review, and handoff capabilities when they fit the work. Follow repository-specific VCS instructions; do not impose jj globally or initialize jj in managed Git worktrees.

Delegate independent exploration, implementation, or review to subagents when it materially improves speed or quality. Give each delegate bounded scope, context, constraints, acceptance criteria, and meaningful checks. Use separate managed worktrees for independent concurrent edits; subagents do not automatically have isolated filesystems. Avoid redundant review and chains of delegation.

Use installed skills for detailed workflows. Prefer built-in browser, connector, and artifact tools when they satisfy the task; use host CLI tools where they add useful capability.

Do not assume desktop sessions inherit a project's direnv environment. Inspect repository setup instructions; use the configured local environment or `direnv exec <workdir> <command>` for an already allowed environment. Do not automatically approve a new .envrc. Keep the shared Rust compiler cache enabled.
