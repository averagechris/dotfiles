---
name: code-review
description: |
  Ordinary behavioral review of a named code change or diff. Judge whether it
  achieves its stated intent. Do not use for routine implementation,
  machine-checked validation, explicit adversarial review (interrogate-me),
  consumer or compatibility analysis (blast-radius), architecture critique
  (how), or forge and PR workflow.
---

# Behavioral review

Judge whether the change achieves its stated intent. This is an ordinary review
of behavior, not a universal checklist.

## Set intent and scope

1. State the intended behavior from the request, change description, relevant
   docs, and code.
2. Establish the exact named change or diff with the repository's VCS. In a jj
   repository, use jj. Review that change only, not unrelated parent work.
3. Read surrounding code only far enough to trace the behavior. Never inspect
   secrets, decrypted material, `.age` files, credentials, or authentication
   material.

Do not turn this into routine implementation, machine-checked validation, an
adversarial `interrogate-me` review, `blast-radius` consumer analysis, `how`
architecture critique, or forge and PR work.

## Trace relevant behavior

Use only the lenses the change calls for:

- Trace reachable happy and failure paths.
- Examine boundaries, state, retries, idempotency, or concurrency only when
  the change touches them.
- Examine callers, contracts, persistence, permissions, or rollout only when
  the change touches them.
- When a guard, fallback, abstraction, or new boundary appears, check its root
  cause and placement.

Keep three principles in view without turning them into style findings:

- Validate at trust boundaries.
- Prefer deletion and direct code before wrappers or state.
- An abstraction should remove demonstrated branching, duplication, hidden
  state, or reader load.

## Require proof

Keep a finding only when it has all four parts:

- a reachable behavior path
- concrete evidence in the change or traced code
- a consequential effect
- a precise file and line or symbol location

Reject hypothetical hardening, taste, speculative edge cases, and nits that
automation should own. Check proof of the intended behavior. Ask for a test
only when it can catch a plausible regression through a stable boundary. Accept
build, lint, manual, integration, or live evidence when appropriate, but make
sure the evidence reaches the claimed behavior rather than merely proving setup.

## Gate findings

Load `subagent-selection` and use its canonical severity and finding gates.
Questions are not defects. No findings is a valid result.

## Return the review

Review is read-only. Do not edit files, leave comments, post to a forge, commit,
push, or mutate external systems.

Apply `impactful-writing` when returning the review directly to the user.
Delegated findings stay plain and compact. For each finding, give the severity,
location, reachable path, evidence, consequence, and a fix direction only when
it is justified. Do not repeat findings in a summary. Include the overall intent
or scope only when it helps the reader understand the result.
