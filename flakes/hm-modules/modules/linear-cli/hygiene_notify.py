"""Notify about Linear hygiene findings from the local check artifact.

Modes:
  summary   Notify when any high/medium findings exist (afternoon report).
  new-high  Notify only about high findings not previously notified (hourly
            watch); dedupe state lives in LINEAR_HYGIENE_STATE_DIR.

Reads the artifact written by `linear hygiene check` (path from
LINEAR_HYGIENE_ARTIFACT). Never fails loudly: a missing or malformed artifact
exits 0 so launchd does not spam error states.
"""

import datetime
import json
import os
import subprocess
import sys


def load_artifact(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def unresolved_findings(artifact):
    findings = artifact.get("findings") or []
    return [f for f in findings if isinstance(f, dict) and not f.get("resolved")]


def notify(title, message, sound=None):
    def esc(text):
        return text.replace("\\", "\\\\").replace('"', '\\"')

    script = f'display notification "{esc(message)}" with title "{esc(title)}"'
    if sound:
        script += f' sound name "{esc(sound)}"'
    subprocess.run(["/usr/bin/osascript", "-e", script], check=False)


def summary(findings):
    high = [f for f in findings if f.get("severity") == "high"]
    medium = [f for f in findings if f.get("severity") == "medium"]
    if not high and not medium:
        print("summary: no high/medium findings; staying quiet")
        return

    parts = []
    if high:
        parts.append(f"{len(high)} high")
    if medium:
        parts.append(f"{len(medium)} medium")
    counts = " and ".join(parts)

    # Name the worst offender so the notification is actionable at a glance.
    worst = (high or medium)[0]
    ident = (worst.get("entity") or {}).get("identifier", "?")
    rule = worst.get("rule", "?")
    message = f"{counts} finding(s) need attention. Worst: {ident} ({rule}). Run: linear hy check --mine"
    notify("Linear Hygiene — afternoon report", message, sound="Ping")
    print(f"summary: notified ({counts})")


def new_high(findings, state_dir):
    state_path = os.path.join(state_dir, "notified-high.json")
    try:
        with open(state_path, "r", encoding="utf-8") as handle:
            state = json.load(handle)
        if not isinstance(state, dict):
            state = {}
    except (OSError, ValueError):
        state = {}

    high = {
        f["dedupeKey"]: f
        for f in findings
        if f.get("severity") == "high" and f.get("dedupeKey")
    }
    fresh_keys = [key for key in high if key not in state]

    if fresh_keys:
        if len(fresh_keys) == 1:
            finding = high[fresh_keys[0]]
            message = finding.get("summary") or fresh_keys[0]
            message = message[:200]
        else:
            idents = ", ".join(
                (high[key].get("entity") or {}).get("identifier", key)
                for key in fresh_keys[:5]
            )
            message = f"{len(fresh_keys)} new high-severity findings: {idents}"
        notify("Linear Hygiene — high severity", message, sound="Sosumi")
        print(f"new-high: notified about {len(fresh_keys)} new finding(s)")
    else:
        print("new-high: no new high findings")

    # Prune resolved keys so a finding that later reappears notifies again.
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    next_state = {key: state.get(key, now) for key in high}
    os.makedirs(state_dir, exist_ok=True)
    tmp_path = state_path + ".tmp"
    with open(tmp_path, "w", encoding="utf-8") as handle:
        json.dump(next_state, handle, indent=1, sort_keys=True)
    os.replace(tmp_path, state_path)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "summary"
    artifact_path = os.environ["LINEAR_HYGIENE_ARTIFACT"]
    state_dir = os.environ["LINEAR_HYGIENE_STATE_DIR"]

    artifact = load_artifact(artifact_path)
    if artifact is None:
        print(f"no readable artifact at {artifact_path}; skipping")
        return

    findings = unresolved_findings(artifact)
    if mode == "summary":
        summary(findings)
    elif mode == "new-high":
        new_high(findings, state_dir)
    else:
        sys.exit(f"unknown mode: {mode}")


if __name__ == "__main__":
    main()
