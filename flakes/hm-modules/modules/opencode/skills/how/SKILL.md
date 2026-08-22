---
name: how
description: "Use for direct questions about how code works, walkthroughs before a change, and placement, ownership, or layering questions. Explains subsystem architecture and runtime flow, and can critique existing architecture. "
---

# How

Explore the codebase to answer "how does X work?" questions. Produce a clear architectural explanation at the level of a senior engineer onboarding onto a subsystem. Build a working mental model rather than annotating source code. Use teach when the user asks to be taught or helped to understand.

Two modes:

1. **Explain** (default). Trace the code and explain the system.
2. **Critique.** Explain first, then assess architectural issues.

## Explain mode

### 1. Understand the question

Identify the requested subsystem, feature flow, architecture, runtime trace, or ownership boundary. If scope is ambiguous, state your best interpretation and proceed. Let the user redirect rather than asking about ambiguity that does not block useful exploration.

### 2. Explore

Explore and trace the relevant code directly by default. Read implementations rather than guessing from names. Follow entry points, data flow, key abstractions, boundaries, and non-obvious behavior until the answer is evidence-backed. Record gaps instead of filling them with guesses.

When breadth or residual uncertainty makes delegation worthwhile, load `subagent-selection` and use focused Explore agents. Split only distinct research angles that can run independently. For example, a broad rate-limiter question might separate state management, request enforcement, and configuration or metrics.

Use the [explorer prompt template](references/explorer-prompt-template.md), filling its placeholders and naming one bounded angle. Parallel exploration is an optimization, not a required panel. Reconcile delegated findings against the code.

### 3. Synthesize

Synthesize the evidence directly into one coherent explanation. Reconcile overlap, contradictions, and gaps from any delegated research.

### 4. Present

Adapt this structure to the question. Omit sections that add no value.

**Overview.** What it is, what it does, and why it exists.

**Key concepts.** The few types, services, or abstractions needed to understand the flow.

**How it works.** Walk from trigger to effect, including data movement and decision points. Cite specific files and symbols. Use code snippets only when the exact code matters.

**Where things live.** Map the files and directories someone needs to start work.

**Gotchas.** Explain surprising behavior, historical artifacts supported by evidence, sharp edges, and unresolved gaps.

## Critique mode

Use this mode when the user asks for architectural issues, problems, or improvements.

### 1. Explain first

Run the proportional explain flow. Understand the architecture before judging it.

### 2. Critique

Apply the [architectural critique rubric](references/architectural-critique-rubric.md) to the actual code. When an independent view would add signal, load `subagent-selection` and use one focused reviewer with the [critic prompt template](references/critic-prompt-template.md). Give it the explanation, relevant paths, and rubric. A reviewer is optional, not a panel.

### 3. Judge findings

Use pragmatic lead judgment rather than counting findings:

- **Act on.** Architectural problems worth fixing now.
- **Consider.** Real concerns whose benefit or timing is unclear.
- **Noted.** Valid observations with low priority.
- **Dismissed.** Wrong, unsupported, missing context, or only a preference.

Present the standalone explanation first, followed by the critique verdict. Keep every retained finding evidence-backed.
