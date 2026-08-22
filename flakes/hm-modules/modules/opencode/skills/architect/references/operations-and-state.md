# Operations and state

At every mutation point, ask:

- What happens if this runs twice?
- What is durable if the process crashes immediately before or after it?
- Can callers retry safely, and how do they learn the outcome?
- Which partial states can exist, who detects them, and who repairs them?
- What timeout, cancellation, or backpressure behavior crosses the boundary?

Make ownership of recovery explicit. Distinguish idempotency, deduplication, transactional guarantees, and compensation. They solve different failures.

Before adding locks or global serialization, ask whether each writer can own a separate object and merge results at the read boundary. Prefer isolated ownership when merge semantics are clear. Use locks or serialization when shared ordering or atomicity is a real invariant, then state lock scope, ordering, contention, and crash behavior.

Include observability only where it supports an operator decision. Name the state, event, or measure that distinguishes success, retry, stuck work, and permanent failure.
