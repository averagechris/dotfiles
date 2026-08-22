# Design review

Compare alternatives only when the fork is costly to reverse. Write concrete caller usage, types, public boundaries, and ownership for each. Alternatives are materially different when they move authority, change the data model, or expose a different contract. Renamed variants do not count.

Judge each shape by:

- which invariant has one clear owner
- which likely change or failure becomes cheaper
- failure and recovery behavior
- compatibility and rollout cost
- reader load, hidden state, and pass-through layers
- how quickly a small experiment can disprove its assumptions

Choose rather than average. Record the reason, rejected alternatives, risks, unknowns, and the smallest proving slice. A proving slice should test the riskiest boundary or assumption with the least durable commitment.

For implementation, hand off the outcome, constraints, caller sketch, types and interfaces, ownership map, migration and operations rules, rejected directions, proving slice, and checkpoint conditions. The design guides implementation; it is not immune to evidence.

Surface material deviations. One difficult edge case may be local complexity. Repeated workarounds, escape hatches, or deviations of the same shape mean an assumption may be wrong. Re-ground that assumption and redesign only the affected shape before broadening the implementation.
