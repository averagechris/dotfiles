---
name: project-map
description: Use when the user explicitly asks to chart, resume, or work through an effort too large or uncertain for one agent session.
---

# Project map

Use a map to track the decisions a large effort needs before delivery. Read [the artifact format](references/artifact-format.md) and apply `impactful-writing` to durable prose.

## Create the map

Use the repository's map location and format. Otherwise use `docs/project-maps/<effort>/map.md`, with child decisions under `issues/`. For work across repositories, choose one canonical home.

State the destination as the concrete decision, specification, or plan the discovery should produce. Keep standing constraints in Notes. Each resolved decision gets a named link and a one-line answer. Put detailed evidence and rationale in the child file.

Create a child when its question is precise. Keep vague areas under `Not yet specified` and conscious exclusions under `Out of scope`. Link decision dependencies by name.

## Work through decisions

Start with the map, then open the relevant child. Use its type to guide the work:

- `research`: gather evidence for a bounded question.
- `prototype`: test an assumption with a disposable artifact.
- `grilling`: discuss a consequential choice with the user.
- `task`: complete a prerequisite that unblocks a decision.

Recommend a direction and bring consequential choices to the user. Record resolved answers in their children and update the map as new questions emerge. Discovery and delivery can require different dependency orders.

Link prototypes, diagrams, or other evidence when they help judge a decision. Each artifact names the question it tests and links back to the decision. Record accepted feedback in the canonical answer. Verified results identify the implementation revision and checks.

Revise short-lived decisions in place. Preserve a superseding record when the old answer still matters to deployed behavior, contracts, or other lasting commitments.

## Move into delivery

Confirm the transition from discovery to implementation with the user. Use the project's delivery tracker when it has one, linking execution work to relevant decisions. One decision can inform several delivery issues, and one issue can implement several decisions.

Finish each pass with what changed, what remains uncertain, and the next decision.
