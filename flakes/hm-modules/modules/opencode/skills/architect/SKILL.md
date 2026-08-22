---
name: architect
description: Use when the user explicitly asks to architect or design, or work creates an expensive-to-reverse public or cross-service contract, persistent data model or wire format, ownership or layering boundary, concurrency or state model, plugin or extension point, or multi-system migration. Do not use for routine features, refactors, bug fixes, clear-precedent placement, explaining or critiquing existing architecture, implemented-diff review, or mere multi-file breadth.
---

# Architect

Shape consequential work before broad implementation. Keep the design concrete, proportional, and easy to disprove.

## Route and ground

- Use local `how` to trace every existing system the design touches. Use `why` only when the rationale for an established boundary or constraint affects the decision. Greenfield work may skip this.
- Treat current behavior and rationale as evidence, not unquestionable precedent.
- Route explanations and architecture critique to `how`. Route implemented-diff review to `code-review`, or to `interrogate-me` only when explicitly requested.
- Never inspect secrets, decrypted material, `.age` files, or credentials.

## Frame the decision

State the outcome, constraints, non-goals, reversal cost, and unresolved product decisions. Ask only when ambiguity would materially change the contract.

Sketch in this order:

1. caller usage
2. domain types and invariants
3. public interfaces and signatures
4. ownership and module map
5. data flow and failure boundaries
6. compatibility and migration

Keep bodies as pseudocode or omit them. Do not add uncompilable source files to embody a sketch.

Load only the references that match the decision:

- [Domain and boundaries](references/domain-and-boundaries.md) for vocabulary, ownership, invariants, interfaces, and abstraction cost.
- [Operations and state](references/operations-and-state.md) for mutation, retries, recovery, concurrency, and partial state.
- [Migration and compatibility](references/migration-and-compatibility.md) for consumer inventory, rollout, versioning, rollback, and removal.
- [Design review](references/design-review.md) for costly forks, selection, implementation handoff, and learning from deviations.

## Demand payoff

For every new abstraction, name the common future change or failure it makes cheaper or safer. Prefer direct code or subtraction when the layer has no demonstrated payoff. Account for reader load, hidden state, and pass-through layers.

Compare two materially distinct, concrete designs only when a costly fork exists. A different ownership model, data model, or public boundary counts. Renaming the same shape does not. When comparison benefits from agents, load `subagent-selection` and follow its canonical policy and table. Do not invent a separate roster or mandatory panel.

Choose a shape and record its rationale, rejected alternatives, risks, and the smallest proving slice that could falsify it before broad implementation.

## Respect scope

Design-only requests stop at the design. If implementation is requested, return a clear implementation packet to the caller. Do not create VCS changes per phase by default. Never publish, deploy, mutate external systems, or implement beyond user scope.

Pause when the user asks, product or API alternatives differ materially, migration or compatibility is substantial, or reversal is about to become expensive. Otherwise reversible work may continue.

Treat material implementation deviations as evidence and surface failed assumptions. Redesign only when repeated deviations or workarounds of the same shape show that the design is wrong. One hard edge case is not enough.

If rationale should persist as an RFC, ADR, or design document, load `technical-writing` and follow the repository format. Do not create one automatically. Apply `impactful-writing` to user-facing prose.

## Return a compact design packet

Include:

- intent, constraints, non-goals, and open decisions
- caller usage
- types, invariants, interfaces, ownership, and data flow
- chosen shape, rationale, and rejected alternatives
- migration and operations concerns when relevant
- risks and unknowns
- smallest proving slice
- checkpoint or implementation decision
