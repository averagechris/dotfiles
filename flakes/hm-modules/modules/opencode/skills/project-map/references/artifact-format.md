# Project-map artifact format

Keep these headings and fields so stock Wayfinder users can navigate the artifacts without translation.

## Map

```markdown
## Destination

<one or two lines describing the end of discovery>

## Notes

<standing constraints; optionally include repository links, tracker initiative
links, or skills to consult when the project has relevant ones>

Decision frontier: [issues/](issues/)

Agents scan this directory for open, unblocked child decisions.

## Decisions so far

- [<decision name>](issues/NN-<slug>.md): <one-line gist>

## Not yet specified

<in-scope areas whose questions cannot yet be stated precisely>

## Out of scope

<explicit exclusions, with a short reason>
```

Open decisions live in child files and do not appear under `Decisions so far`. Keep each resolved entry to one named link and one line. Detailed answers belong in the child only.

## Child decision

Use a stable numbered filename such as `issues/01-storage-boundary.md` unless repository instructions prescribe another identity or path. These local issues are decision questions, not a one-to-one plan for external delivery issues.

```markdown
# <decision name>

Type: research | prototype | grilling | task
Status: open | claimed | resolved
Blocked by: <named relative links, or "none">

## Question

<one precise question>

## Answer

<the answer and concise rationale; leave empty until resolved>

## Artifacts

- Proposal: [Boundary options](../artifacts/boundary-options.md) — compares the
  alternatives for this decision
- Prototype: [Interaction demo](../artifacts/interaction-demo/) — tests the
  proposed behavior
- Review: [Review notes](../artifacts/review-notes.md) — input awaiting
  reconciliation into this decision
- Verified result: [Delivered behavior](../artifacts/verified-result.md) — checks
  the resolved answer against the delivered state

## Delivery links

- [<external delivery issue name>](<tracker URL>)
```

`Blocked by` records decision dependencies, not delivery scheduling. Prefer named relative links over bare numbers. `Artifacts` is optional. Each artifact states the question or claim it helps evaluate and links back to this named decision or the canonical map. The `Answer` remains authoritative.

Artifacts are projections or evidence, not a second decision record. Reconcile accepted comments or annotations into the canonical map or child decision. A verified-result artifact identifies the exact implementation revision or delivered state and links its checks or evidence.

`Delivery links` is optional and may be empty. It records named external tracker links, not a one-to-one mapping. One decision may inform several delivery issues, and one delivery issue may implement several decisions. External delivery issues link back to the canonical map and the relevant named decisions.

When an existing Wayfinder or tracker contract adds required metadata, retain it. Do not rename the fields or headings above.
