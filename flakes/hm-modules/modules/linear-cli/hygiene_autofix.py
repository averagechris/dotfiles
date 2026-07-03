"""Agentically auto-resolve low-stakes Linear hygiene findings.

Reads the local `linear hygiene check` artifact, selects findings from an
allowlisted set of rules (missing domain/type label, missing estimate,
missing priority), gathers issue context plus allowed values, and asks a
cheap agent model for decisions in one batched call. The agent only decides;
this script validates every decision against allowed values and applies the
updates via the linear CLI. Unclear cases are skipped.

Env:
  LINEAR_HYGIENE_ARTIFACT            artifact path
  LINEAR_HYGIENE_STATE_DIR           attempts-tracking state dir
  LINEAR_HYGIENE_SCOPE_ARGS          JSON list of scope args (e.g. ["--mine"])
  LINEAR_HYGIENE_AUTOFIX_RULES       JSON list of rule ids to handle
  LINEAR_HYGIENE_AUTOFIX_MAX         max findings per run
  LINEAR_HYGIENE_AGENT_CMD           JSON list; prompt appended as final arg
  LINEAR_HYGIENE_ESTIMATION_GUIDANCE optional estimation rubric text
"""

import datetime
import json
import os
import re
import subprocess
import sys

# rule id -> (action, label group). Only rules where a wrong-but-reasonable
# value is low-impact belong here; everything else stays with the human.
RULE_ACTIONS = {
    "issue-missing-domain": ("set_label", "domain"),
    "issue-missing-type": ("set_label", "type"),
    "missing-estimate-in-cycle": ("set_estimate", None),
    "missing-priority": ("set_priority", None),
}

VALID_ESTIMATES = {0, 1, 2, 3, 5, 8}
VALID_PRIORITIES = {1, 2, 3, 4}
MAX_ATTEMPTS = 3
AGENT_TIMEOUT_SECONDS = 900


def log(message):
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{stamp}] {message}", flush=True)


def run_linear(args, timeout=120):
    result = subprocess.run(
        ["linear", "--no-pager", *args],
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(f"linear {' '.join(args)} failed: {result.stderr.strip()[:400]}")
    return result.stdout


def load_state(state_path):
    try:
        with open(state_path, "r", encoding="utf-8") as handle:
            state = json.load(handle)
        return state if isinstance(state, dict) else {}
    except (OSError, ValueError):
        return {}


def save_state(state_path, state):
    os.makedirs(os.path.dirname(state_path), exist_ok=True)
    tmp = state_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(state, handle, indent=1, sort_keys=True)
    os.replace(tmp, state_path)


def issue_context(identifier):
    raw = json.loads(run_linear(["i", "get", identifier, "--output", "json", "--compact"]))
    labels = [n.get("name") for n in (raw.get("labels") or {}).get("nodes", []) if n.get("name")]
    description = (raw.get("description") or "")[:2000]
    return {
        "identifier": identifier,
        "title": raw.get("title"),
        "description": description,
        "labels": labels,
        "team": (raw.get("team") or {}).get("name"),
        "project": (raw.get("project") or {}).get("name"),
        "state": (raw.get("state") or {}).get("name"),
        "estimate": raw.get("estimate"),
        "priority": raw.get("priority"),
    }


def label_options(group):
    raw = json.loads(
        run_linear(
            ["context", "options", "labels", "--group", group, "--output", "json", "--compact"]
        )
    )
    groups = raw.get("labelGroups") or []
    if not groups:
        return []
    return [
        {"name": opt.get("name"), "description": opt.get("description")}
        for opt in groups[0].get("options", [])
        if opt.get("name")
    ]


def build_prompt(tasks, groups, estimation_guidance):
    instructions = f"""You are a Linear workflow hygiene assistant. For each finding below,
decide the missing value only when it is a reasonably obvious choice given the
issue's title, description, labels, project, and team. When genuinely unclear,
skip. Getting an estimate or label slightly wrong is low-impact, so prefer a
sensible decision over skipping when the issue content gives any real signal.

Actions:
- set_estimate: fibonacci points, one of 0, 1, 2, 3, 5, 8.
  {estimation_guidance or "Estimate complexity and uncertainty, not hours: 1=tiny, 2=small, 3=medium, 5=large, 8=too big (skip instead of guessing 8)."}
- set_label: choose exactly one label NAME from the allowed options for the
  finding's label group. Never invent a label.
- set_priority: 1=urgent, 2=high, 3=normal, 4=low. Routine work defaults to 3;
  use 1-2 only when the issue text clearly signals urgency.
- skip: when the right value is not reasonably inferable.

Respond with ONLY a JSON object wrapped between BEGIN_DECISIONS and
END_DECISIONS lines, shaped exactly like:
BEGIN_DECISIONS
{{"decisions": [{{"key": "<finding key>", "action": "set_estimate", "value": 3, "reason": "short why"}}]}}
END_DECISIONS

Include one decision entry for every finding key. Do not run commands or take
any other action; just answer."""

    payload = {
        "label_group_options": groups,
        "findings": tasks,
    }
    return instructions + "\n\nFindings and context:\n" + json.dumps(payload, indent=1)


def extract_decisions(output):
    matches = re.findall(r"BEGIN_DECISIONS\s*(\{.*?\})\s*END_DECISIONS", output, re.DOTALL)
    if not matches:
        raise RuntimeError("agent output contained no BEGIN_DECISIONS/END_DECISIONS block")
    parsed = json.loads(matches[-1])
    decisions = parsed.get("decisions")
    if not isinstance(decisions, list):
        raise RuntimeError("agent output decisions is not a list")
    return decisions


def apply_decision(task, decision, groups):
    action = decision.get("action")
    value = decision.get("value")
    ident = task["context"]["identifier"]

    if action == "skip" or action is None:
        return "skipped", decision.get("reason") or "agent skipped"
    if action != task["action"]:
        return "invalid", f"agent chose action {action!r}, expected {task['action']!r}"

    if action == "set_estimate":
        if not isinstance(value, int) or value not in VALID_ESTIMATES:
            return "invalid", f"estimate {value!r} not in {sorted(VALID_ESTIMATES)}"
        run_linear(["--quiet", "i", "update", ident, "-e", str(value)])
    elif action == "set_priority":
        if not isinstance(value, int) or value not in VALID_PRIORITIES:
            return "invalid", f"priority {value!r} not in {sorted(VALID_PRIORITIES)}"
        run_linear(["--quiet", "i", "update", ident, "-p", str(value)])
    elif action == "set_label":
        allowed = {opt["name"] for opt in groups.get(task["label_group"], [])}
        if not isinstance(value, str) or value not in allowed:
            return "invalid", f"label {value!r} not in group {task['label_group']!r} options"
        # `linear i update -l` replaces the label set, so include existing labels.
        labels = list(dict.fromkeys(task["context"]["labels"] + [value]))
        args = ["--quiet", "i", "update", ident]
        for label in labels:
            args += ["-l", label]
        run_linear(args)
    else:
        return "invalid", f"unknown action {action!r}"

    return "applied", f"{action}={value!r} ({decision.get('reason', 'no reason given')})"


def main():
    artifact_path = os.environ["LINEAR_HYGIENE_ARTIFACT"]
    state_dir = os.environ["LINEAR_HYGIENE_STATE_DIR"]
    scope_args = json.loads(os.environ.get("LINEAR_HYGIENE_SCOPE_ARGS", '["--mine"]'))
    allowed_rules = set(json.loads(os.environ["LINEAR_HYGIENE_AUTOFIX_RULES"]))
    max_findings = int(os.environ.get("LINEAR_HYGIENE_AUTOFIX_MAX", "8"))
    agent_cmd = json.loads(os.environ["LINEAR_HYGIENE_AGENT_CMD"])
    estimation_guidance = os.environ.get("LINEAR_HYGIENE_ESTIMATION_GUIDANCE", "")

    unknown = allowed_rules - set(RULE_ACTIONS)
    if unknown:
        sys.exit(f"unsupported autofix rules: {sorted(unknown)}")

    try:
        with open(artifact_path, "r", encoding="utf-8") as handle:
            artifact = json.load(handle)
    except (OSError, ValueError):
        log(f"no readable artifact at {artifact_path}; nothing to do")
        return

    state_path = os.path.join(state_dir, "autofix-attempts.json")
    attempts = load_state(state_path)

    candidates = []
    for finding in artifact.get("findings") or []:
        if not isinstance(finding, dict) or finding.get("resolved"):
            continue
        rule = finding.get("rule")
        key = finding.get("dedupeKey")
        if rule not in allowed_rules or not key:
            continue
        if (finding.get("entity") or {}).get("type") != "issue":
            continue
        if attempts.get(key, {}).get("count", 0) >= MAX_ATTEMPTS:
            continue
        candidates.append(finding)

    candidates = candidates[:max_findings]
    if not candidates:
        log("no autofixable findings")
        return
    log(f"considering {len(candidates)} finding(s): "
        + ", ".join(f["dedupeKey"] for f in candidates))

    tasks = []
    groups = {}
    for finding in candidates:
        action, group = RULE_ACTIONS[finding["rule"]]
        ident = finding["entity"]["identifier"]
        try:
            context = issue_context(ident)
        except (RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
            log(f"{finding['dedupeKey']}: context fetch failed: {error}")
            continue
        if group and group not in groups:
            try:
                groups[group] = label_options(group)
            except (RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
                log(f"label options for group {group!r} failed: {error}")
                groups[group] = []
        tasks.append(
            {
                "key": finding["dedupeKey"],
                "rule": finding["rule"],
                "action": action,
                "label_group": group,
                "finding_summary": finding.get("summary"),
                "context": context,
            }
        )
    if not tasks:
        log("no findings with usable context")
        return

    prompt = build_prompt(tasks, groups, estimation_guidance)
    log(f"invoking agent: {' '.join(agent_cmd)} <prompt {len(prompt)} chars>")
    result = subprocess.run(
        agent_cmd + [prompt],
        capture_output=True,
        text=True,
        timeout=AGENT_TIMEOUT_SECONDS,
        cwd=os.path.expanduser("~"),
        check=False,
    )
    if result.returncode != 0:
        sys.exit(f"agent command failed ({result.returncode}): {result.stderr.strip()[:800]}")

    try:
        decisions = {d.get("key"): d for d in extract_decisions(result.stdout) if isinstance(d, dict)}
    except (RuntimeError, ValueError) as error:
        sys.exit(f"could not parse agent decisions: {error}\n--- agent stdout tail ---\n{result.stdout[-1500:]}")

    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    applied = 0
    for task in tasks:
        key = task["key"]
        decision = decisions.get(key)
        if decision is None:
            outcome, detail = "skipped", "agent returned no decision"
        else:
            try:
                outcome, detail = apply_decision(task, decision, groups)
            except (RuntimeError, subprocess.TimeoutExpired) as error:
                outcome, detail = "error", str(error)
        log(f"{key}: {outcome} — {detail}")
        record = attempts.setdefault(key, {"count": 0})
        record["count"] += 1
        record["last"] = now
        record["outcome"] = outcome
        if outcome == "applied":
            applied += 1

    # Keep attempt records only for keys still present, so resolved findings
    # that reappear later get fresh attempts.
    current_keys = {task["key"] for task in tasks} | {
        f.get("dedupeKey")
        for f in artifact.get("findings") or []
        if isinstance(f, dict)
    }
    attempts = {k: v for k, v in attempts.items() if k in current_keys}
    save_state(state_path, attempts)

    log(f"applied {applied}/{len(tasks)} decision(s); refreshing artifact")
    try:
        run_linear(
            ["--quiet", "--retry", "3", "hygiene", "check", *scope_args, "--output", "json"],
            timeout=300,
        )
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        log(f"artifact refresh failed: {error}")


if __name__ == "__main__":
    main()
