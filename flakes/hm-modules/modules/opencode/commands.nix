{
  review-pr = ''
    ---
    description: Review a GitHub pull request from a PR URL
    ---

    Review the GitHub pull request at $ARGUMENTS.

    Load and use the `github-pr-review` skill, and use `changes-review-core` as
    the underlying review methodology.

    Execute this flow explicitly:

    Important: `review-artifact-generate`, `review-artifact-write`,
    `review-artifact-render`, and `review-github-post` are OpenCode tools, not
    shell executables. Call them as tools. Do not run `type`, `command -v`, or
    ad-hoc shell fallbacks for them. If one of these tools is unavailable, stop
    and report that the OpenCode review tools are not loaded.

    1. Use `gh` to fetch the PR metadata needed for the
       `review-artifact-generate` tool.
    2. By default, attempt to check out the PR locally unless the user
       explicitly says not to.
    3. Verify the local checkout matches the PR head SHA before treating local
       code as review evidence.
    4. Use `gh pr diff` to fetch the unified diff text.
    5. Pass the PR metadata JSON, diff text, and an explicit local repo path
       when local checkout context is available into the
       `review-artifact-generate` tool.
    6. Review and refine the generated artifact using `changes-review-core`.
    7. Produce a human change walkthrough before comment triage. Explain the PR
       as a reviewer-oriented tour, not just a defect list:
       - what changed and why, in dependency / execution order
       - the main files or modules and how data flows between them
       - behavior changes, API or CLI surface changes, and test coverage
       - risk areas and what evidence supports or reduces each risk
       - 2-5 suggested deep-dive questions the user can ask next
    8. Persist the refined artifact with the `review-artifact-write` tool.
    9. Render the default terminal digest with the `review-artifact-render` tool.
    10. Use the `functions.question` tool to work through every candidate
        comment with the user after the evidence is stable. For each candidate
        comment, offer explicit choices: approve as-is, refine wording, change
        severity/target, convert inline/top-level, reject/drop, or hold for
        later. Apply the user's choices to the artifact before posting.
    11. Stop there unless the user explicitly asks to post.
    12. If the user explicitly asks to post, call the `review-github-post` tool
        with the artifact path and an explicit final review state. Do not craft
        a separate `gh api` review payload unless the user explicitly forbids
        the posting tool.

    Generate a draft review artifact JSON payload first, refine it as needed,
    then persist it with `review-artifact-write`. Treat the persisted artifact
    as the source of truth for any later rendering or posting flow. If the user
    asks to adjust tone or drop comments before posting, update and persist the
    artifact again, then post from that updated artifact.

    Produce a terminal-first review digest that includes:

    1. PR summary and stated intent
    2. linked issue or ticket context when available
    3. walkthrough of the changes in review order
    4. change hotspots and risky files
    5. findings classified by severity and comment target
    6. a complete draft posting plan with:
       - inline comments
       - top-level review text
       - suggested final review state
       - per-comment status: approved, needs wording, convert, drop, or hold

    Keep the transcript compact. Do not dump large code excerpts or reprint the
    full artifact. Small selected excerpts are fine only when especially useful,
    and the renderer should own that presentation.

    Do not use `functions.question` early as a workflow-debug step. Only use it
    after the review evidence is stabilized, the walkthrough is presented, and
    the draft comments are ready for triage.

    Do not post anything to GitHub unless explicitly asked after presenting the
    draft plan.
  '';
}
