---
name: sideshow-work-story
description: Use when the user asks to use sideshow to show off work, make an impact/story deck, or synthesize agent sessions with issue tracker and code-change evidence.
---

# sideshow Work Story

Use `sideshow` to turn recent work into an evidence-backed narrative or deck.
This is especially relevant for prompts like “look at my OpenCode sessions this
week, cross-reference issue tracker work and code changes, and help me tell the
story of the impact.”

## Workflow

1. Gather bounded evidence first: search agent history with `ctx`, related issue
   tracker work with available tools (`linear` for Linear, `srht todo` for
   todo.sr.ht), and code changes with available VCS/forge tools (`jj`, `gh`, or
   `srht git`). Use exact dates, project names, and keywords from the user;
   prefer JSON or compact output.
2. Separate facts from interpretation. Extract concrete before/after measures,
   shipped PRs, review/incident/customer signals, and open follow-ups.
3. Shape a concise arc: context → problem → interventions → measured impact →
   risks or next bets. Keep citations or source links in speaker notes.
4. If the user wants a deck, create a `sideshow` source directory, run
   `sideshow themes --format json`, pick a theme that fits the audience, and
   author small `slides/*.html` or `slides/*.md` fragments.
5. Verify before delivery:

   ```bash
   sideshow check <deck-dir>
   sideshow build <deck-dir>
   ```

   If browser automation is available, open the exact built HTML path and run
   `sideshow.audit()` plus screenshots before presenting it.

## Notes

- `sideshow` config lives at `~/.config/sideshow/config.toml`; tool paths may be
  managed there for `tailwindcss`, `ffmpeg`, `vhs`, and `aws`.
- Do not invent metrics. If impact is qualitative or inferred, label it that way
  and suggest what to measure next.
- Prefer a stronger story with fewer claims over a busy deck full of weak links.
