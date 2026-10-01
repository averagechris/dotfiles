---
name: test-curation
description: Use when finalizing a code change or PR with added or changed tests, to decide which tests deserve permanent retention.
---

# Curate changed tests

Review tests added or materially changed in this change. Keep a test when it protects meaningful behavior through a stable boundary, catches a plausible regression, and earns its maintenance and CI cost.

Configuration and contract tests can meet that bar. Checks that repeat literals, mirror implementation details, or duplicate compiler guarantees rarely do. Temporary development checks can be deleted once they have served their purpose.

For review, explain which tests earn their place. For implementation, make the justified removals and run the relevant checks. Report the reasons briefly.
