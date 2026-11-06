"""Suremac-only coordinator for verified certificate hold attestations."""
from __future__ import annotations

import argparse
import fcntl
import os
import re
from pathlib import Path
import socket
import stat
import tempfile
import time
from types import SimpleNamespace

from maintenance import cli, gate
from maintenance.common import Blocked, GitHub, REPOSITORY, atomic_json, digest, dumps, json_bytes, read_json, require
from maintenance.controller import policy_at

ATTEST_WORKFLOW = ".github/workflows/maintenance-attest.yml"
ATTEST_ARTIFACT = "maintenance-host-attestation"
DEDUP_SECONDS = 20 * 3600


def token_from_file(path: Path) -> str:
    require(path.is_absolute(), "attestor token file path must be absolute")
    info = path.lstat()
    require(stat.S_ISREG(info.st_mode) and stat.S_IMODE(info.st_mode) == 0o600,
            "attestor token file must be a regular mode-0600 file")
    require(info.st_uid in {0, os.geteuid()}, "attestor token file has an unexpected owner")
    value = path.read_text().strip()
    require(re.fullmatch(r"[A-Za-z0-9_]+", value), "invalid attestor token file")
    return value


def _run_by_title(api, workflow, title, base, actor=None):
    runs = api.pages(f"/repos/{REPOSITORY}/actions/workflows/{Path(workflow).name}/runs?event=workflow_dispatch", "workflow_runs")
    found = [run for run in runs if run.get("display_title") == title and
             run.get("path") == workflow and run.get("event") == "workflow_dispatch" and
             run.get("head_branch") == "main" and run.get("head_sha") == base and
             (actor is None or run.get("actor", {}).get("login") == actor)]
    return max(found, key=lambda run: run["id"]) if found else None


def _run_local_attestor(api, policy, expected, now):
    policy_bytes = api.file("maintenance/policy.json", expected["base"])
    with tempfile.TemporaryDirectory(prefix="maintenance-host-attestor-") as temp:
        trusted = Path(temp) / "trusted"
        trusted.mkdir()
        (trusted / "maintenance").mkdir()
        (trusted / "maintenance/policy.json").write_bytes(policy_bytes)
        identity = Path(temp) / "identity.json"
        identity.write_text(dumps(expected) + "\n")
        output = Path(temp) / "attestation.json"
        cli.attest(SimpleNamespace(trusted=trusted, identity=identity, output=output))
        result = json_bytes(output.read_bytes())
    gate.verify_identity(result, expected)
    gate.fresh(result.get("created_at"), policy["max_evidence_age_seconds"], max(now, int(time.time())))
    require(result.get("host") == "suremac" and result.get("check") == "macos-keychain" and
            result.get("status") == "passed", "local host attestor returned invalid evidence")
    return result


def tick(state_dir, api, app_login, attestor_login, now=None):
    now = int(time.time() if now is None else now)
    require(socket.gethostname().split(".")[0] == "suremac", "host attestor can run only on suremac")
    require(attestor_login and not attestor_login.endswith("[bot]"), "host attestor needs its separately approved scoped user token")
    require(api.get("/user").get("login") == attestor_login, "attestor GitHub token belongs to a different identity")
    state_dir = Path(state_dir)
    state_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    state_dir.chmod(0o700)
    with (state_dir / "attestor.lock").open("a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        state_path = state_dir / "state.json"
        state = read_json(state_path) if state_path.exists() else {"schema": 1, "submitted": {}}
        base = api.get(f"/repos/{REPOSITORY}/git/ref/heads/main")["object"]["sha"]
        policy, policy_hash = policy_at(api, base)
        hold = policy["holds"]["emudhra"]
        prs = api.pages(f"/repos/{REPOSITORY}/pulls?state=open&base={policy['base_branch']}")
        candidates = [pr for pr in prs if pr.get("state") == "open" and not pr.get("draft") and
                      pr.get("user", {}).get("login") == app_login and
                      pr.get("head", {}).get("repo", {}).get("full_name") == REPOSITORY and
                      pr.get("base", {}).get("repo", {}).get("full_name") == REPOSITORY and
                      pr.get("base", {}).get("ref") == policy["base_branch"] and
                      pr.get("base", {}).get("sha") == base and
                      pr.get("head", {}).get("ref", "").startswith(policy["branch_prefix"])]
        require(len(candidates) <= 1, "multiple maintenance candidates need owner review")
        if not candidates:
            return {"phase": "idle"}
        pr = candidates[0]
        expected = gate.identity(policy_hash, pr["number"], base, pr["head"]["sha"])
        gate.verify_pr(api, policy, expected, app_login)
        sources = gate.verify_sources(api, policy, expected)
        if sources["nixpkgs"] == hold["revision"]:
            return {"phase": "not_required", "head": expected["head"]}

        title = "Maintenance validation " + expected["head"]
        validation = _run_by_title(api, policy["validation_workflow"], title, base)
        require(validation and validation.get("status") == "completed" and validation.get("conclusion") == "success",
                "candidate has no successful trusted native validation run")
        evidence = gate.verify_validation(api, policy, expected, validation["id"], now)
        key = expected["head"]
        previous = state["submitted"].get(key)
        host_title = "Maintenance host attestation " + expected["head"]
        existing = _run_by_title(api, ATTEST_WORKFLOW, host_title, base, attestor_login)
        if existing:
            if existing.get("status") == "completed" and existing.get("conclusion") == "success":
                try:
                    attached = gate.attach_host_attestation(api, policy, expected, evidence, existing["id"], attestor_login, now)
                    observed = attached["host_attestations"]["macos-keychain"]["created_at"]
                    if now - observed < DEDUP_SECONDS:
                        return {"phase": "complete", "head": key, "run_id": existing["id"]}
                except Blocked:
                    # Stale/expired evidence is never reused. A new read-only
                    # host measurement may replace it; final CI verifies anew.
                    pass
            elif existing.get("status") != "completed":
                return {"phase": "in_progress", "head": key, "run_id": existing["id"]}
        if previous and previous.get("identity") == expected and now - previous.get("created_at", 0) < DEDUP_SECONDS:
            return {"phase": "submitted", "head": key}

        attestation = _run_local_attestor(api, policy, expected, now)
        input_value = dumps(attestation)
        state["submitted"][key] = {"identity": expected, "created_at": now,
                                    "attestation_sha256": digest(input_value.encode())}
        atomic_json(state_path, state)
        api.post(f"/repos/{REPOSITORY}/actions/workflows/{Path(ATTEST_WORKFLOW).name}/dispatches", {
            "ref": "main", "inputs": {"head": expected["head"], "base": base,
                                        "pr": str(expected["pr"]), "attestation": input_value},
        })
        return {"phase": "submitted", "head": key}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    command = sub.add_parser("tick")
    command.add_argument("--state", type=Path, required=True)
    command.add_argument("--app-login", required=True)
    command.add_argument("--attestor-login", required=True)
    command.add_argument("--token-file", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        api = GitHub(token_from_file(args.token_file))
        result = tick(args.state, api, args.app_login, args.attestor_login)
        print(dumps(result))
    except (Blocked, OSError, KeyError, ValueError) as exc:
        message = str(exc) if isinstance(exc, Blocked) else "invalid or unavailable host attestation input"
        parser.exit(1, f"host attestation blocked: {message}\n")


if __name__ == "__main__":
    main()
