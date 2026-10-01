---
name: technical-writing
description: Use only for substantive engineer-facing artifacts such as docs, RFCs, PRDs, roadmaps, design docs, and technical blog posts. Do not use for ordinary conversation, answers, status updates, code review, or routine PR and commit text.
---

# Technical writing

Apply `impactful-writing`. Keep reference material neutral and distinguish evidence from opinion.

## Draft around the reader's task

Read [document modes](references/document-modes.md). Choose the mode that fits the reader's question or task. Organize around what they need to do or look up.

Check the current code, configuration, and tests before describing behavior. Use exact names, paths, flags, defaults, and measured values. Include a command to regenerate derived tables or counts.

Put prerequisites before procedures. Give runnable commands, expected results, and useful recovery steps. Use consistent terms and descriptive links.

For design documents, explain the problem, constraints, proposed behavior, alternatives, and tradeoffs. Cover migration, failure handling, and rollout where they affect the decision. Distinguish facts, assumptions, open questions, and commitments.

Review with the [engineering doc checklist](references/engineering-doc-checklist.md). Use the artifact's existing format when it fits the task.

## Source traditions

This guidance adapts [Diátaxis](https://diataxis.fr/), the [Google developer documentation style guide](https://developers.google.com/style), [ASD-STE100 Simplified Technical English](https://www.asd-ste100.org/), and John R. Kohl's *The Global English Style Guide*. These sources inform document modes, task-focused instructions, controlled terminology, and ambiguity checks. `impactful-writing` remains the local authority for general prose style.
