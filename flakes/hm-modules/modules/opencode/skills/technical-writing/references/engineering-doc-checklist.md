# Review an engineering document

## Purpose and structure

- Does the document name its audience, task or question, and intended outcome?
- Does each section support one document mode? Are mode changes split or linked clearly?
- Do headings expose reader tasks and lookup targets?
- Do links describe their destinations, and do relative links resolve?

## Engineering accuracy

- Does every claim match the current code, configuration, tests, or cited evidence?
- Are symbols, paths, flags, commands, configuration keys, defaults, and measured values exact?
- Can readers regenerate generated counts, trees, or tables with a documented command?
- Does reference material cover the facts needed for correct use, including limits, outputs, and errors?
- Does the text distinguish facts and evidence from decisions, assumptions, commitments, and opinion?

## Procedures

- Are prerequisites and starting conditions explicit?
- Does each step contain one action, with its condition before the action?
- Are commands runnable from the stated directory and environment?
- Does the procedure name expected output or another visible checkpoint?
- Where failure is likely or costly, does the document explain diagnosis, recovery, or rollback?

## Designs and decisions

- Are goals, non-goals, constraints, and current behavior explicit?
- Does the proposed design name its interfaces, boundaries, and data flow?
- Are alternatives, rationale, tradeoffs, and unresolved risks visible?
- Where relevant, does the document cover compatibility, migration, security, failure handling, observability, testing, rollout, and rollback?

## Ambiguity and terminology

- Does each concept keep one name throughout the document and match the codebase name?
- Does every pronoun have one clear referent?
- Can long noun strings be expanded into clauses?
- Are `only` and `not` next to what they modify?
- Can `and`, `or`, a missing article, or an omitted verb produce a second reading?

For example, replace "If exceeded, CI fails" with "If the import count exceeds the budget, CI fails." The revision names the condition and removes the ambiguous subject.

## Final review

- Run or test procedures where practical. Check links and rendered formatting.
- Apply `impactful-writing` to the complete draft.
- Remove stale context and repetition. Keep durable facts and explain how to verify facts likely to change.
- Read once as the intended user. Confirm that the next action or answer is easy to find.

These checks adapt task-focused guidance from the [Google developer documentation style guide](https://developers.google.com/style), instruction controls from [ASD-STE100](https://www.asd-ste100.org/), and ambiguity guidance from John R. Kohl's *The Global English Style Guide*.
