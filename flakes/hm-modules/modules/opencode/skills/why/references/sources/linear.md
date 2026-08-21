# Linear tickets

Linear is the current source for product and project context in this setup. Issues, comments, parents, projects, labels, status updates, attachments, and linked PRs can explain customer needs, deadlines, scope changes, and business constraints.

## Search

Use the available Linear skill, CLI, or integration. Read its instructions or help rather than assuming a schema. Adapt this playbook to another available tracker when needed.

1. Open ticket IDs from commits and PRs. Read descriptions, comments, and history.
2. Search feature names, symbols, error text, and business terms with several phrasings.
3. Walk parent, child, duplicate, and related issue links. Parents often contain the rationale.
4. Inspect the owning project and its current documents or updates.
5. Record labels, milestones, deadlines, and linked PRs.

## Strong evidence

Prefer a specific problem statement, a decision comment that compares approaches, an initiative parent, or a substantive attached spec. Labels such as `customer:<name>`, `incident-followup`, `compliance`, or `perf-regression` support context but rarely prove intent alone.

## Failure modes

Read the full history because scope changes. Treat boilerplate "Why" text as weak evidence. Compare stale tickets with the ship date and implementation. Follow duplicates to the canonical issue. Record inaccessible workspace content as a gap.

## Return

For each ticket, provide ID, title, URL, exact motivation text, author and dates, labels, parent, project, and relevant history.
