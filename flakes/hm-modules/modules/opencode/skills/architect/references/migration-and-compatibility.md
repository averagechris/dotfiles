# Migration and compatibility

Inventory the contract before changing it: callers, readers, writers, stored records, messages, APIs, jobs, operational tooling, and independently deployed systems. Separate controlled consumers from contractual compatibility.

When every caller is controlled and compatibility is not promised, migrate callers and remove the old path in one wave. Avoid dual paths that buy nothing.

Otherwise design the transition explicitly:

- old and new reader and writer combinations
- additive or versioned formats
- sequencing across deployments and backfills
- mixed-state duration and observability
- rollback after new data exists
- ownership of cleanup and the condition for removing compatibility code

Prefer expand, migrate, contract when deployment independence requires it. Never call a rollout reversible unless old code can read the resulting state or a tested conversion restores it.
