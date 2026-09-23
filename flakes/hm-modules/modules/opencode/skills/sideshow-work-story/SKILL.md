---
name: sideshow-work-story
description: Use when the user asks to synthesize work into an evidence-backed impact story, including bounded agent-history, tracker, and code-change research. If an actual deck is requested, hand a bounded story packet to sideshow-deck-author for deck mechanics.
---

# sideshow Work Story

Turn recent work into an evidence-backed narrative and a bounded handoff for any
requested deck.
This is especially relevant for prompts like “look at my OpenCode sessions this
week, cross-reference issue tracker work and code changes, and help me tell the
story of the impact.”

## Workflow

1. Gather bounded evidence first: search agent history with `ctx`, related issue
   tracker work with available tools (`gh issue` for GitHub Issues, `linear` for
   Linear, `srht todo` for todo.sr.ht), and code changes with available
   VCS/forge tools (`jj`, `gh`, or `srht git`). Use exact dates, project names,
   and keywords from the user;
   prefer JSON or compact output.
2. Separate facts from interpretation. Extract concrete before/after measures,
   shipped PRs, review/incident/customer signals, and open follow-ups.
3. Shape a concise arc: context → problem → interventions → measured impact →
   risks or next bets. Keep citations or source links in speaker notes.
4. Return a bounded story packet containing the audience and purpose, time and
   project bounds, narrative arc, strongest claims, evidence links or citations,
   caveats, and open questions. Do not include an unbounded history dump.
5. If the user asks to create or revise an actual deck, load
   `sideshow-deck-author` only when that skill is available, and pass it that
   packet. If it is absent (including with a supported source-less package
   override), return the bounded story packet and clearly state that deck
   authoring is unavailable. Do not attempt to load a missing skill or duplicate
   its mechanics. Deck creation, revision,
   themes, fragment authoring, project-artifact explain/prototype/verify
   mechanics, checks, builds, review, and publishing belong to deck-author; do
   not restate or improvise those command contracts here.

## Notes

- Do not invent metrics. If impact is qualitative or inferred, label it that way
  and suggest what to measure next.
- Prefer a stronger story with fewer claims over a busy narrative full of weak
  links.
