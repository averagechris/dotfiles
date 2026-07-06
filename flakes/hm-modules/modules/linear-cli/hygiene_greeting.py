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
  GITHUB_PR_HYGIENE_ARTIFACT        optional cached `jj pr hygiene --json` path
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


def load_json(path):
    if not path:
        return None
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def parse_iso(value):
    try:
        return datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (AttributeError, TypeError, ValueError):
        return None


def pr_expected_inputs():
    try:
        workdirs = json.loads(os.environ.get("GITHUB_PR_HYGIENE_WORKDIRS", "[]"))
    except ValueError:
        workdirs = []
    try:
        limit = int(os.environ.get("GITHUB_PR_HYGIENE_LIMIT", "0"))
        ttl_seconds = int(os.environ.get("GITHUB_PR_HYGIENE_TTL_SECONDS", "0"))
    except ValueError:
        limit = 0
        ttl_seconds = 0
    return {
        "search": os.environ.get("GITHUB_PR_HYGIENE_SEARCH", ""),
        "limit": limit,
        "ttlSeconds": ttl_seconds,
        "workdirs": workdirs if isinstance(workdirs, list) else [],
        "noWorkspaces": os.environ.get("GITHUB_PR_HYGIENE_NO_WORKSPACES", "false")
        == "true",
    }


def pr_cache_fresh(artifact, now):
    if not isinstance(artifact, dict):
        return False
    cache = artifact.get("cache") or {}
    if not isinstance(cache, dict):
        return False
    if cache.get("inputs") != pr_expected_inputs():
        return False
    expires = parse_iso(cache.get("expiresAt"))
    return expires is not None and now < expires


def actionable_prs(artifact):
    if not isinstance(artifact, dict):
        return []
    prs = artifact.get("prs") or []
    if not isinstance(prs, list):
        return []
    return [
        pr
        for pr in prs
        if isinstance(pr, dict)
        and pr.get("status") in {"needs-fix", "ready", "needs-review"}
    ]


def main():
    if os.environ.get("LINEAR_HYGIENE_GREETING", "1") == "0":
        return
    if not sys.stdout.isatty():
        return

    artifact_path = os.environ["LINEAR_HYGIENE_ARTIFACT"]
    state_dir = os.environ["LINEAR_HYGIENE_STATE_DIR"]
    interval = int(os.environ.get("LINEAR_HYGIENE_GREETING_INTERVAL", "60"))

    artifact = load_json(artifact_path)
    if artifact is None:
        artifact = {}

    now = datetime.datetime.now(datetime.timezone.utc)
    generated = parse_iso(artifact.get("generatedAt"))
    linear_fresh = generated is not None and now - generated <= MAX_ARTIFACT_AGE

    findings = [
        f
        for f in artifact.get("findings") or []
        if linear_fresh and isinstance(f, dict) and not f.get("resolved")
    ]
    high = [f for f in findings if f.get("severity") == "high"]
    medium = [f for f in findings if f.get("severity") == "medium"]

    pr_artifact = load_json(os.environ.get("GITHUB_PR_HYGIENE_ARTIFACT", "")) or {}
    prs = actionable_prs(pr_artifact) if pr_cache_fresh(pr_artifact, now) else []

    if not high and not medium and not prs:
        return
    if rate_limited(state_dir, interval):
        return

    counts = []
    if high:
        counts.append(f"{RED}{len(high)} high{RESET}")
    if medium:
        counts.append(f"{YELLOW}{len(medium)} medium{RESET}")
    age = humanize(now - generated) if generated else "unknown age"
    nudge = random.choice(NUDGES)

    lines = []
    if high or medium:
        lines.append(
            f"🧹 {BOLD}Linear hygiene{RESET}: {', '.join(counts)} {DIM}(as of {age} — {nudge}){RESET}"
        )
    for finding in high[:3]:
        summary = (finding.get("summary") or finding.get("dedupeKey", "?"))[:100]
        lines.append(f"   {RED}⚑{RESET} {summary}")
    if len(high) > 3:
        lines.append(f"   {RED}⚑{RESET} …and {len(high) - 3} more high")
    if medium:
        by_rule = Counter(f.get("rule", "?") for f in medium)
        rollup = " · ".join(f"{rule} ×{count}" for rule, count in by_rule.most_common(4))
        lines.append(f"   {YELLOW}~{RESET} {rollup}")

    if prs:
        pr_cache = pr_artifact.get("cache") or {}
        pr_generated = parse_iso(pr_cache.get("generatedAt"))
        pr_age = humanize(now - pr_generated) if pr_generated else "unknown age"
        lines.append(
            f"🔀 {BOLD}GitHub PR hygiene{RESET}: {len(prs)} actionable {DIM}(cached {pr_age}){RESET}"
        )
        for pr in prs[:3]:
            repo = pr.get("repo", "?")
            number = pr.get("number", "?")
            status = pr.get("status", "unknown")
            effort = pr.get("reviewEffort", "?")
            title = (pr.get("title") or "?")[:90]
            color = RED if status == "needs-fix" else YELLOW
            lines.append(f"   {color}PR{RESET} {repo}#{number} · {status} · {effort} · {title}")
        if len(prs) > 3:
            lines.append(f"   {YELLOW}PR{RESET} …and {len(prs) - 3} more actionable PRs")

    hint_parts = ["linear hy check --mine", "autofix: linear-hygiene-autofix"]
    if prs:
        hint_parts.append("prs: github-pr-hygiene-report")
    lines.append(f"   {DIM}↪ {' · '.join(hint_parts)}{RESET}")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
