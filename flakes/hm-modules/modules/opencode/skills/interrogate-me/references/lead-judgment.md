# Lead judgment

Act as the lead reviewer, not a vote counter. Reviewers see limited context and are asked to be adversarial. Verify their claims and decide what matters for this change.

## Filter the findings

- Trace hypothetical failures through real callers, types, and validation. Dismiss unreachable cases.
- Reject preferences presented as defects. A different design matters only when the current one has a concrete cost or failure.
- Account for repository conventions, constraints, planned follow-up work, and unchanged code.
- Scrutinize correctness and security findings even when only one reviewer found them.
- Treat agreement as a reason to investigate, not proof. Preserve disagreements and explain what the code shows.
- Apply the canonical severity gates. Low-severity findings and nits do not create work by themselves.

## Decide

- **Act on.** A verified correctness, security, or maintainability problem that should block this change.
- **Consider.** A real concern, but its benefit, cost, or timing is uncertain.
- **Noted.** A valid observation with no useful action now.
- **Dismissed.** Wrong, unreachable, duplicative, outside scope, or only a preference.

For each item, name the reviewers, retain the original severity, cite the file and line or symbol, and give a one-line reason for the category. Include a direction only when the evidence justifies one. Keep the Act on list selective. An empty category is fine.
