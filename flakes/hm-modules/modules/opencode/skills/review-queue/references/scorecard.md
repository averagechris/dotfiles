# Council scorecards

Use the full applicable roster in `advisor-council` for full scorecards. The same rubric applies to the routine reviewers who support automatic approval. Give each seat the same pinned PR revision and relevant evidence. Reviewers score independently before seeing anyone else's verdict. A permitted reviewer who lacks source access may identify questions. Record the evidence gap and leave their ratings blank.

Ask each advisor for these five ratings per PR, on a 0–100 scale, each with its own explanation of at most one paragraph. Ask for code or check references where they support the reason.

| Rating | What to judge |
| --- | --- |
| Completeness | Does the change satisfy the agreed scope and cover affected callers? |
| Correctness | Does it produce the intended behavior on reachable paths? |
| Robustness | Does it handle edge cases, failure, compatibility, and rollout as needed? |
| Simplicity | Is the implementation as small and maintainable as the problem allows? |
| Should merge | How strongly would this advisor recommend merging the reviewed revision? Name any condition that could change the recommendation. |

Keep one row per PR and advisor, with the PR linked and the reviewed revision visible. Use the advisor's own numbers and reasons. Leave missing ratings blank and show why, including pending or unavailable seats. Mark rows for a changed revision as stale and exclude them from the current verdict. Call out disagreements and any verified blocker in the recap. Scores express reviewer judgment and are one input to the skill's approval checks.

In T3 Code, use `html_preview` then `html_render` for an inline scorecard. Elsewhere, provide a self-contained local HTML scorecard with a compact Markdown summary. A score button or link opens only that score's paragraph. Include accessible labels that name the advisor, rating, and value. Escape PR and advisor text as data, validate links, and load assets locally or inline. If interactive HTML is unavailable, use a Markdown table with links to the corresponding short reasons or list the reasons below each row. Keep private report content in the current session or local artifact.
