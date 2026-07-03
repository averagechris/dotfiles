"""Print a small, fun Linear hygiene nudge when opening a new shell.

Reads the local `linear hygiene check` artifact only (no network). Prints
nothing when there are no unresolved high/medium findings, when stdout is not
a terminal, when the artifact is stale, or within the rate-limit window
(stamp file mtime under LINEAR_HYGIENE_STATE_DIR).

Env:
  LINEAR_HYGIENE_ARTIFACT           artifact path
  LINEAR_HYGIENE_STATE_DIR          state dir for the rate-limit stamp
  LINEAR_HYGIENE_GREETING_INTERVAL  minimum minutes between printouts (0 = always)
  LINEAR_HYGIENE_GREETING           set to 0 to disable entirely
"""

import datetime
import json
import os
import random
import sys
from collections import Counter

MAX_ARTIFACT_AGE = datetime.timedelta(days=7)

NUDGES = [
    "a little tidying goes a long way",
    "future you says thanks",
    "small sweeps, clean backlog",
    "the board gremlins are restless",
    "entropy never sleeps, but it can be estimated",
    "tickets age like milk, not wine",
    "five minutes now beats a sprint-review scramble",
]

YELLOW = "\033[33m"
RED = "\033[31m"
DIM = "\033[2m"
BOLD = "\033[1m"
RESET = "\033[0m"


def humanize(delta):
    seconds = int(delta.total_seconds())
    if seconds < 3600:
        return f"{max(seconds // 60, 0)}m ago"
    if seconds < 86400:
        return f"{seconds // 3600}h ago"
    return f"{seconds // 86400}d ago"


def rate_limited(state_dir, interval_minutes):
    if interval_minutes <= 0:
        return False
    stamp = os.path.join(state_dir, "greeting-stamp")
    try:
        age = datetime.datetime.now().timestamp() - os.path.getmtime(stamp)
        if age < interval_minutes * 60:
            return True
    except OSError:
        pass
    os.makedirs(state_dir, exist_ok=True)
    with open(stamp, "w", encoding="utf-8"):
        pass
    return False


def main():
    if os.environ.get("LINEAR_HYGIENE_GREETING", "1") == "0":
        return
    if not sys.stdout.isatty():
        return

    artifact_path = os.environ["LINEAR_HYGIENE_ARTIFACT"]
    state_dir = os.environ["LINEAR_HYGIENE_STATE_DIR"]
    interval = int(os.environ.get("LINEAR_HYGIENE_GREETING_INTERVAL", "60"))

    try:
        with open(artifact_path, "r", encoding="utf-8") as handle:
            artifact = json.load(handle)
    except (OSError, ValueError):
        return

    now = datetime.datetime.now(datetime.timezone.utc)
    try:
        generated = datetime.datetime.fromisoformat(
            artifact.get("generatedAt", "").replace("Z", "+00:00")
        )
    except ValueError:
        return
    if now - generated > MAX_ARTIFACT_AGE:
        return

    findings = [
        f
        for f in artifact.get("findings") or []
        if isinstance(f, dict) and not f.get("resolved")
    ]
    high = [f for f in findings if f.get("severity") == "high"]
    medium = [f for f in findings if f.get("severity") == "medium"]
    if not high and not medium:
        return
    if rate_limited(state_dir, interval):
        return

    counts = []
    if high:
        counts.append(f"{RED}{len(high)} high{RESET}")
    if medium:
        counts.append(f"{YELLOW}{len(medium)} medium{RESET}")
    age = humanize(now - generated)
    nudge = random.choice(NUDGES)

    lines = [
        f"🧹 {BOLD}Linear hygiene{RESET}: {', '.join(counts)} {DIM}(as of {age} — {nudge}){RESET}"
    ]
    for finding in high[:3]:
        summary = (finding.get("summary") or finding.get("dedupeKey", "?"))[:100]
        lines.append(f"   {RED}⚑{RESET} {summary}")
    if len(high) > 3:
        lines.append(f"   {RED}⚑{RESET} …and {len(high) - 3} more high")
    if medium:
        by_rule = Counter(f.get("rule", "?") for f in medium)
        rollup = " · ".join(f"{rule} ×{count}" for rule, count in by_rule.most_common(4))
        lines.append(f"   {YELLOW}~{RESET} {rollup}")
    lines.append(
        f"   {DIM}↪ linear hy check --mine · autofix: linear-hygiene-autofix{RESET}"
    )
    print("\n".join(lines))


if __name__ == "__main__":
    main()
