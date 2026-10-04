# Grem preferences reference

The canonical source is
[`flakes/hosts/suremac/grem/PREFERENCES.md`](../flakes/hosts/suremac/grem/PREFERENCES.md).
It holds a concise starting draft for grem's work personality and communication
preferences. Chris reviews and refines the text before adoption.

## Nix integration

The suremac Home Manager configuration links the source through
`xdg.configFile."grem/PREFERENCES.md".source`. After a separately requested
Darwin activation, the reference is available at
`$XDG_CONFIG_HOME/grem/PREFERENCES.md`, normally
`/Users/chris/.config/grem/PREFERENCES.md`.

Edit the repository source. The deployed path is a read-only Nix reference,
not another editable copy. Editing or evaluating the configuration does not
deploy it. Activation updates only this reference file. It does not adopt the
preferences or synchronize them with app instructions, saved personality, or
custom rules. No watcher, hook, agent loader, or synchronization job reads it.

This file is deliberately separate from the automatic Codex guidance described
in [Codex](codex.md). It is not an auto-loaded `AGENTS.md`, a skill, or executable
policy. The configuration does not add its contents to Codex context or
`extraInstructions`, and it does not change OpenCode or Michi.

## Task routing and fallback

The preferences reference the "Model selection" section of
[`modules/codex/AGENTS.md`](../flakes/hm-modules/modules/codex/AGENTS.md)
as the single routing policy source. They do not copy the policy or import
OpenCode's named agent roster. Launch tasks with explicit model and reasoning
selections when applying that policy.

Suremac declares Sol 6.1 with low reasoning through `dotfiles.codex.settings`.
This is an activation-time TOML fallback, separate from intentional task routing.
Omitted desktop task selections use saved desktop defaults. Their relationship
to TOML must be verified before reporting that the live desktop fallback changed.
See [Codex](codex.md) for precedence and activation limits.

## Review and adoption

1. Edit the canonical source and review the diff with Chris.
2. Refine the draft and merge the agreed change into `main`.
3. Chris separately asks grem to read the merged version and adopt it.

Until that explicit request, opening the file for review has no adoption
meaning. A deployed reference may lag behind `main` until a later activation.
Use the merged source when reviewing which version to adopt.

Permission custom rules stay in the app. This document and the preferences
file grant no tool access, authorize no actions, and override no app permissions.
They contain no credentials or private work details.

## Source of the draft

The starting point is Michi's
[`SOUL.md`](../flakes/hosts/thorny/michi/SOUL.md), particularly its temperament,
voice, and work-and-trust guidance. The draft adapts curiosity, using available
context before asking for help, reasoned opinions,
explicit uncertainty, plain correction of mistakes, and truthful reporting.
It retains the useful-answer-first style and punctuation preferences shared
with the [impactful-writing skill](../flakes/hm-modules/modules/opencode/skills/impactful-writing/SKILL.md).

Michi's kitten identity, mischief, roleplay, affectionate reactions, Spanish
embellishments, and personal-chat behavior are omitted. These files evolve
independently. Changing Michi does not update grem's preferences.

## Validation

Parse `flakes/hosts/suremac/configuration.nix` with `nix-instantiate --parse`.
Evaluate the suremac Home Manager `xdg.configFile."grem/PREFERENCES.md"` entry
and confirm its source matches the canonical text. Check that the generated
Codex context does not include the draft. No Darwin switch is needed to review
or validate this change.
