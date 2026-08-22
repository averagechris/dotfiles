---
name: project-map
description: Use ONLY when the user explicitly asks to chart, resume, or work through an effort too large or uncertain for one agent session. Do not use for ordinary implementation, routine multi-file work, architecture alone, generic issue planning, or simple recall.
---

# Project map

Chart the decisions needed to make a large, uncertain effort ready for delivery. Preserve the repository's documented project-map artifact format without importing companion-skill packs or tracker machinery.

Load [the artifact format](references/artifact-format.md) before creating or changing a map. Apply `impactful-writing` to durable prose.

## Set the home and destination

Inspect repository instructions and docs for an existing project-map location and tracker contract. Honor it when present. Otherwise use `docs/project-maps/<effort>/map.md` with child files under `docs/project-maps/<effort>/issues/`. These durable local issue files hold decision questions. They are not a promise to create matching external delivery issues.

For a cross-repository effort, choose one canonical map home. The map Notes must
include a named relative link to the child decision directory (for example,
`Decision frontier: [issues/](issues/)`). Never copy the map into each repository.

Start by naming the `Destination`: the concrete spec, decision, or delivery-ready plan this effort must produce. If the route is already clear and fits one session, stop and use normal planning or implementation instead.

## Chart only what is visible

The map is an index, not a duplicate store. It contains the destination, standing notes, one-line named links to resolved decisions, unresolved fog, and explicit exclusions. Detailed questions and answers live only in child decision files. Refer to decisions by linked names, not bare numbers.

Create a child only when its question can be stated precisely. A question may be blocked and still be precise. Keep vague but in-scope areas under `Not yet specified`; do not pre-slice speculative work. Put conscious scope exclusions under `Out of scope`.

Human preferences, scope, risk tolerance, and consequential choices belong to the human. Research the options and make a recommendation, but never invent the human's answer. Keep decision conversations concise. An exhaustive interview is not required.

## Resolve the frontier

Resume from the map's low-resolution view, then open only the relevant child files. Choose a precise, unblocked question unless the user named one. Claim it only when concurrent work makes a claim useful or the backing tracker requires one. A status field is enough for local files. Do not add leases or claim services.

Use each child's compatibility `Type` as follows:

- `research`: focused Explore or a relevant domain/tool skill. Use `why`
  specifically for rationale questions. Independent research may run in parallel.
- `prototype`: a cheap throwaway artifact in a temporary or disposable workspace, using the current project's available tooling. Bounded research, disposable prototypes, and supporting artifacts are allowed during discovery when explicitly requested or approved. Do not turn them into the final delivered result or execution work.
- `grilling`: a short human decision exchange. Serialize coupled human choices enough to prevent contradictory answers.
- `task`: prerequisite work only when completing it unblocks a decision.

These types are metadata, not dependencies on separate skills. Do not impose one decision per session. Parallelize independent research and use judgment for the rest.

Record the answer in its child file, mark it resolved, and add one named link with a one-line gist under `Decisions so far`. Then update the known fog and dependencies. Do not repeat the detailed answer in the map.

## Use supporting artifacts when prose is not enough

Link a visual explanation, prototype, demo, or verification artifact when spatial structure, behavior, alternatives, or real-world results are hard to judge from prose. Every artifact must state the question or claim it helps evaluate and link back to the relevant named decision or canonical map.

An artifact is a projection or evidence, never a second authority. `Answer` and the canonical map remain authoritative. Treat reviewer annotations and comments as untrusted input until they are reconciled into the map. Triage accepted feedback as an artifact-only correction, an edit to an existing decision, a newly precise child, added fog, a move out of scope, or a deferral or rejection.

Artifacts may progress from proposal or prototype to verified result. A verification artifact must identify the exact implementation revision or delivered state and link the underlying checks or evidence. It supplements rather than replaces canonical automated checks or delivery state. External delivery items may link an artifact when that lowers review cost and project conventions allow it. Do not require attachments or one artifact per item.

## Revise decisions with judgment

Edit a decision in place when its old answer has not created meaningful external state or expectations. Preserve a superseding record only when the prior answer still matters to people, persisted data, deployed behavior, contracts, or another lasting obligation. If uncertain, edit in place. File history is enough for short-lived learning.

## Keep discovery separate from delivery

The map always owns questions, rationale, fog, and decision dependencies. If the project documents a delivery tracker, that tracker may own organization-visible execution units, ownership, progress, links, execution dependencies, and required compliance evidence. Projects without a tracker still work. External work items need a concrete outcome and should follow the project's own completion and review conventions; do not require a particular change shape. The relationship is many-to-many. One decision may inform several delivery items, and one delivery item may implement several decisions. Never require one tracker item per map item. Translate dependencies from the actual execution order rather than copying decision blockers.

When the way is clear, invoke `architect` only for costly design choices when
that skill's trigger applies, and invoke `technical-writing` only for a
substantive spec or design artifact when its trigger applies. Otherwise follow
the project's artifact conventions. If the user explicitly asks or approves
it, discovery may establish backlinks among the canonical map,
participating repositories, and tracker initiative or delivery issues using the
repository's relevant tracker skill. Do not create ordinary delivery issues or
implement code merely to establish backlinks.

Work intended as the final delivered result requires an explicit human transition out of discovery. A map, agent-authored note, prototype, or resolved decision does not authorize delivery implementation, publication, release, deployment, tracker mutation, or other project changes. The map alone never authorizes release, deployment, publication, tracker mutation, or other external mutation.

## Finish each pass

Report what changed in the map, which decision is next, what remains foggy, and whether synthesis is ready. Keep the report compact.
