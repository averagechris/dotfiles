---
name: blast-radius
description: "Use ONLY for explicit blast-radius requests such as 'blast radius', 'what could this break elsewhere', compatibility or consumer impact before shipping, or a small diff the user asks to distrust. Do not use for routine code review or ordinary implementation."
---

# Blast radius

Find what a change could break outside its diff before it ships. A caller list is only a starting point. The useful result traces breakage that symbol search misses and tests the assumptions that make the change safe.

## Scope and safety

- Analyze the change. Do not edit production code, commit, push, deploy, or mutate external systems.
- You may run safe real tests or a temporary script against the code that will ship. Keep temporary work outside production code and remove it when done.
- Never inspect secrets, credentials, authentication material, decrypted files, or `.age` files.
- Do not invoke `interrogate-me` unless the user separately asks for that adversarial workflow.
- For broad or high-consequence work, load `subagent-selection`. Its policy and table are canonical. Use independent analysis only when the consequence or remaining uncertainty warrants it.

## Process

1. Read the change and establish its intent. Use the local `how` skill for mechanics. Use the local `why` skill only when historical rationale or safety constraints matter. Do not run a full `why` investigation by default.
2. Trace direct callers, then search beyond symbols. Check contracts, data and wire formats, configuration, persistence, lifecycle and async timing, generated code, other languages or services, downstream consumers, rollout and feature flags, and pinned dependency behavior.
3. When external behavior matters, verify the exact pinned dependency version, its source, and local patches. Test the version the project ships, not current online documentation.
4. Identify the one or two load-bearing safety assumptions. Prefer assumptions that, if true, rule out several suspected failures.
5. Push each assumption as cheaply as possible down the proof ladder:
   1. Claim. State the assumption.
   2. Source. Cite the relevant code or dependency source.
   3. Bad path ruled out. Trace the failure path and show where it becomes unreachable.
   4. Real test or script. Execute shipped code and fail clearly if the assumption is false.
   5. Running-system reproduction. Reproduce the behavior in the real application when safe and practical.
6. Prefer executable proof. If an assumption cannot reach a real test or reproduction, mark it unproven. Do not round its confidence up.
7. Record each risk with its reachable path, evidence, likelihood, consequence, and cheapest verification. Separate retained risks from risks that evidence cleared.

Search names, schemas, serialized fields, config keys, storage keys, generated artifacts, protocol values, and dependency call sites. A symbol grep can miss consumers that copy data, deserialize in another language, depend on timing, or pin older behavior.

## Output

Apply `impactful-writing`. Keep the report compact and cite files, lines, dependency source, and executed commands where useful.

- **Change and intent.** State what changed and the intended behavior.
- **Load-bearing assumptions.** Give each assumption, its proof level, evidence, and result. Mark it unproven when it stopped before a real test or reproduction.
- **Retained risks.** Include the reachable path, evidence, likelihood, consequence, and cheapest verification.
- **Cleared risks.** State what was checked and the evidence that ruled it out.
- **Before-ship verification.** List the cheapest tests or reproductions that catch the remaining plausible failures.
