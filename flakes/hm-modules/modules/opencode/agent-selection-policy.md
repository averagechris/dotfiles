Route by residual uncertainty and consequence, using the cheapest agent likely
to succeed:

The scorecard is descriptive, not a weighted utility score or an instruction to
maximize intelligence. For routine, reversible, verifiable work, cost and speed
dominate once an agent clears the capability threshold. Consequence and residual
uncertainty raise that threshold; they do not justify buying maximum capability
by default. Select for cost-effective success with verification.

- `tiny`: essentially free mechanics: PR/CI watching, metadata, cleanup, exact
  command/read-back checks, and tiny deterministic edits or reviews.
- `luna`: bounded medium-complexity work or deterministic review that needs some
  reasoning. Escalate with evidence rather than looping when the task outgrows
  its clear boundary.
- `minion`: the default and bulk implementation tier, and the default ordinary
  behavioral reviewer. The orchestrator removes uncertainty with clear
  acceptance criteria, and Minion then reliably clears the required capability
  threshold; its routine coding value is independent of intrinsic model cost or
  raw score. It handles sustained coding, broader context, tool sequencing, and
  judgment across multiple files.
- `build`: reserve for implementation or review whose ambiguity, breadth,
  investigation, or coordination cannot reasonably be removed by upfront
  planning and decomposition. Ordinary multi-file coding is not enough.
- `wise`: reserve for the hardest, high-consequence work. Generally require at
  least two risk signals: security/auth/crypto, irreversible production impact,
  cross-system contracts, competing architectures, failed or conflicting
  lower-tier attempts, or taste-heavy simplification where the wrong direction
  is costly.
- `explore`: focused codebase research rather than implementation.

Invest upfront in decomposition and hand Minion an implementation packet with
scope, relevant context, constraints, acceptance criteria, and checks. The
orchestrator defines normal tasks; Wise may define architecture or high-risk
constraints when warranted. Once uncertainty becomes a checklist, hand routine
implementation to Minion, bounded work to Luna, and mechanics to Tiny. A lower
tier may retry or verify once after a miss, then escalate with the failed check
and remaining uncertainty instead of looping. If implementation contradicts a
packet's design assumptions, treat that as evidence: stop and report the failed
assumption instead of forcing the design through. If a session or task outgrows
its packet, escalate or split it rather than expanding its scope.

## Nested delegation

Include explicit sub-delegation guidance in every handoff prompt; do not rely on
shared delegate prompt text to supply it. Normally tell the delegate to complete
the assigned packet directly. When a small, separable handoff could materially
improve research, mechanics, or verification, permit it explicitly while asking
the delegate to keep it sparse and avoid chains. Build may be given this option
when unresolved complexity justifies it.

For Minion, say that it owns the implementation and may use Explore for focused
research or Tiny for mechanical support where useful, but must not pass
implementation or build work to another coding agent. Its task permissions
enforce that boundary.

Tell delegates to use the task tool for justified handoffs so work remains
visible in the parent session. Also tell them not to use `opencode run` as a
routine delegation escape hatch because it hides work from the session tree and
bypasses the intended routing context. This is guidance, not a permission ban.

## Review routing

- Skip delegated review for fully mechanical, machine-checked changes.
- Use Tiny for exact deterministic re-review and review logistics.
- Use Luna for bounded deterministic review needing some reasoning.
- Use Minion by default for ordinary behavioral review.
- Use Build for broad or ambiguous review.
- Use Wise only for high-consequence, adversarial, or cross-system review. Allow
  one initial Wise review and at most one follow-up to validate blocker or
  high-severity remediation or a material high-risk design change, even when
  localized. Do not repeat Wise review merely because a blocker remains: a
  further pass requires materially different remediation or design, or a new
  risk class; otherwise escalate the unresolved issue to the user.

Severity-gate findings. Blockers and high-severity findings must be resolved;
use judgment for medium findings. Low-severity findings and nits do not
automatically expand implementation or trigger another review pass.
