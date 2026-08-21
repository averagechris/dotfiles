---
name: teach
description: Use when the user asks to be taught a code change, concept, feature, subsystem, or runtime flow. Builds a plain mental model with how and why. Do not use for ordinary answers.
---

# Teach

Help the person genuinely understand the subject. This is a teaching dialogue, not a wrapper around an ordinary answer.

When the user says "teach me" or "help me understand," use this as the outer workflow even if the question also asks how something works. Use `how` only as supporting investigation.

Load `impactful-writing` and apply it to the explanation. Do not repeat its catalog. Return the explanation itself, not a report of skill use.

## Set the lesson

Infer what the person needs from their question and the conversation. Consider whether they are preparing to change, review, debug, or first encounter the subject. Do not quiz them for context they have already supplied.

Choose the few ideas needed for a useful mental model. Start with the smallest complete explanation, usually one or two sentences. Add depth at the person's pace rather than delivering the whole investigation at once.

## Build the mental model

- Begin with a plain definition tied to the case at hand.
- Explain concrete mechanisms and the path from trigger to effect. A list of symbols, files, or constants is reference material, not teaching.
- Use examples, code, diffs, or runtime observations when they make the mechanism easier to see.
- Use a diagram only when it clarifies structure or flow. For several moving parts, prefer a short sequence in which each diagram adds one idea. Do not decorate the answer with a figure.
- Keep uncertainty visible. Never turn an inference into a fact for the sake of a smooth explanation.

Use the local `how` skill when the mechanics need codebase exploration. Use the local `why` skill when rationale or history matters. Use either or both selectively, and let them own their exploration and evidence work. Do not duplicate those instructions. Preserve `why`'s confidence language when weaving its findings into the explanation.

Do not add quizzes, pacing theater, or generic offers. Stop once the current layer is complete and let the person direct the next turn.

Use `technical-writing` only when the user asks for a durable technical artifact. Ordinary teaching dialogue does not need it.
