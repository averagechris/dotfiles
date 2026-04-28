{
  review-pr = ''
    ---
    description: Review a GitHub pull request from a PR URL
    ---

    Review the GitHub pull request at $ARGUMENTS.

    Load and use the `github-pr-review` skill, and use `changes-review-core` as
    the underlying review methodology.

    Execute this flow explicitly:

    1. Use `gh` to fetch the PR metadata needed for `review-artifact-generate`.
    2. By default, attempt to check out the PR locally unless the user
       explicitly says not to.
    3. Verify the local checkout matches the PR head SHA before treating local
       code as review evidence.
    4. Use `gh pr diff` to fetch the unified diff text.
    5. Pass the PR metadata JSON, diff text, and an explicit local repo path
       when local checkout context is available into
       `review-artifact-generate`.
    6. Review and refine the generated artifact using `changes-review-core`.
    7. Persist the refined artifact with `review-artifact-write`.
    8. Render the default terminal digest with `review-artifact-render`.
    9. Use a question-chooser loop to work through the candidate comments with
       the user after the evidence is stable.
    10. Stop there unless the user explicitly asks to post.
    11. If the user explicitly asks to post, call `review-github-post` with the
       artifact path and an explicit final review state.

    Generate a draft review artifact JSON payload first, refine it as needed,
    then persist it with `review-artifact-write`. Treat the persisted artifact
    as the source of truth for any later posting flow.

    Produce a terminal-first review digest that includes:

    1. PR summary and stated intent
    2. linked issue or ticket context when available
    3. change hotspots and risky files
    4. findings classified by severity and comment target
    5. a complete draft posting plan with:
       - inline comments
       - top-level review text
       - suggested final review state

    Keep the transcript compact. Do not dump large code excerpts or reprint the
    full artifact. Small selected excerpts are fine only when especially useful,
    and the renderer should own that presentation.

    Do not use the chooser early as a workflow-debug step. Only use it after the
    review evidence is stabilized and the draft comments are ready for triage.

    Do not post anything to GitHub unless explicitly asked after presenting the
    draft plan.
  '';
}
