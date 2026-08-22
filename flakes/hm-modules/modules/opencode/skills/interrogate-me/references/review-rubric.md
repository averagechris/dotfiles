# Review rubric

Use only the lenses that fit the change. Prefer a few findings with traced evidence over a long list.

## Correctness and failure paths

- Check the stated behavior on happy paths, failures, boundaries, retries, partial runs, and concurrent access.
- Trace callers, inputs, state changes, and error handling. Do not claim that a value can be missing unless a reachable path allows it.
- Check idempotency and recovery when an operation can run twice or stop halfway.

## Root cause and placement

- Decide whether the change fixes the cause or hides a broken invariant with a guard, retry, cast, fallback, or comment.
- Read callers, callees, types, and sibling modules when needed.
- Check that validation sits at boundaries and feature logic lives in its canonical layer.
- Prefer existing helpers. Flag duplicated contracts or compatibility paths only when current callers make them needless.

## Structure and maintainability

- Look for avoidable branches, scattered special cases, mixed abstraction levels, and coupling that makes a likely next change harder.
- Prefer direct code over magic, thin wrappers, loose object shapes, and cast-heavy contracts.
- Recommend structural simplification only when it removes demonstrated complexity. Do not demand abstraction for its own sake or rewrite working code to match a preference.
- Check whether independent work is needlessly serial or related updates can leave partial state. Ignore micro-optimizations without user impact.

## Verification

- Check whether tests and assertions cover behavior rather than implementation details.
- Ask for a permanent test only when it protects meaningful behavior through a stable boundary and justifies its maintenance and CI cost. A useful development check need not ship. For an integration boundary, follow the full path.
- Verify real outputs and state rather than proxies, cached indicators, or delegated self-reports.

## Security

- Trace untrusted input to dangerous sinks, authorization decisions, secret exposure, and time-of-check to time-of-use races.
- Report security concerns only with a reachable path and concrete consequence.

## Review discipline

- **Blocker.** The review cannot establish safety or correctness because essential context, validation, or a core premise is missing.
- **High.** A reachable correctness, security, data-loss, or contract failure that must be fixed before the change proceeds.
- **Medium.** A real behavioral or maintainability problem that needs judgment about cost and timing.
- **Low.** A limited issue or improvement that does not justify expanding the change by itself.
- Do not report style nits unless they cause a demonstrated readability or maintenance problem.
- Do not ask for a rewrite without showing what is broken or unnecessarily complex.
- Say `No findings.` when nothing meets the bar.
