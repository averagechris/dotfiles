---
name: technical-writing
description: Use only for substantive engineer-facing artifacts such as docs, RFCs, PRDs, roadmaps, design docs, and technical blog posts. Do not use for ordinary conversation, answers, status updates, code review, or routine PR and commit text.
---

# Technical writing

Load `impactful-writing` before drafting or reviewing. Apply its general prose filter where it fits the artifact. The artifact rules here win when they conflict: reference material stays neutral, document structure stays deliberate, and opinion belongs only in explanation or clearly marked commentary. Do not reproduce the general writing catalog here.

This skill adds control over document purpose, audience, engineering truth, navigability, procedures, reference completeness, durable structure, and ambiguity.

## Start with purpose and evidence

1. Name the audience, the task or question, and the concrete outcome.
2. Choose the document mode before drafting. Read [document modes](references/document-modes.md). Split mixed modes into linked sections or documents when the reader's task changes.
3. Inspect the current code, configuration, tests, and related docs. Treat the repository as the source of names and behavior.
4. Outline around reader tasks and lookup needs, not the order in which the system was built.
5. Draft, then apply the [engineering doc checklist](references/engineering-doc-checklist.md).

## Write what the system does

- Use exact symbols, paths, flags, commands, configuration keys, and measured values.
- Verify every technical claim against the code and current repository state. Do not fill gaps with plausible behavior.
- For generated counts, trees, or tables, include the command that regenerates them.
- Put prerequisites and conditions before actions. Name expected results and add failure or recovery notes when they help the reader proceed.
- Use useful headings and descriptive links so readers can scan, navigate, and return for lookup.
- Use one term per concept. Rewrite ambiguous pronouns, dense noun strings, and unclear placement of `only` or `not`.

## Respect artifact boundaries

- PRDs and roadmaps separate facts, decisions, assumptions, open questions, owners, dates, and success measures. Do not invent certainty or commitments.
- Blog posts and explanations may take a position, but identify what is evidence and what is opinion.
- RFCs, ADRs, and design docs state goals, non-goals, constraints, the proposed design, alternatives and rationale, consequences, and unresolved risks. Cover migration, compatibility, security, failure handling, observability, testing, rollout, and rollback when they matter.
- READMEs, how-tos, and tutorials provide runnable procedures and expected results.

Routine PR descriptions and commit messages need only `impactful-writing`. Use this skill for them only when the user asks for substantive document-like treatment.

Use the artifact's existing format when it already captures these facts. Do not turn a focused document into a template exercise.

## Source traditions

This guidance adapts [Diátaxis](https://diataxis.fr/), the [Google developer documentation style guide](https://developers.google.com/style), [ASD-STE100 Simplified Technical English](https://www.asd-ste100.org/), and John R. Kohl's *The Global English Style Guide*. These sources inform document modes, task-focused instructions, controlled terminology, and ambiguity checks. `impactful-writing` remains the local authority for general prose style.
