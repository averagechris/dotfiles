#!/usr/bin/env python3
"""Fixed-purpose entry points for Michi and the trusted GitHub workflows."""
from __future__ import annotations

import argparse
import base64
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import time
import uuid

# Direct invocation from a Nix store package and -m invocation both work.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from maintenance.common import (Blocked, GitHub, REPOSITORY, atomic_json, credential,
                                digest, dumps, load_policy, read_json, require, sha)
from maintenance import gate
from maintenance.policy import check_contents, safe_path


def github():
    # GitHub jobs explicitly supply this ephemeral token. No gh credential store.
    return GitHub(credential("github-token", "GH_TOKEN"))


def env_identity(policy_hash):
    return gate.identity(policy_hash, int(os.environ["M_PR"]), os.environ["M_BASE"], os.environ["M_HEAD"])


def prepare(args):
    policy, policy_hash = load_policy(args.trusted)
    expected = env_identity(policy_hash)
    api = github()
    gate.verify_pr(api, policy, expected, os.environ.get("MAINTENANCE_APP_LOGIN", ""))
    sources = gate.verify_sources(api, policy, expected)
    expected["ancestry"] = gate.verify_ancestry(api, policy, sources["nixpkgs"])
    atomic_json(args.output, expected)


def close_superseded(api, policy, current_pr, app_login):
    for pr in api.pages(f"/repos/{REPOSITORY}/pulls?state=open&base=main"):
        if (pr["number"] == current_pr or pr.get("user", {}).get("login") != app_login or
                pr.get("head", {}).get("repo", {}).get("full_name") != REPOSITORY or
                not pr.get("head", {}).get("ref", "").startswith(policy["branch_prefix"])):
            continue
        commits = api.pages(f"/repos/{REPOSITORY}/pulls/{pr['number']}/commits")
        require(len(commits) == 1 and commits[0]["sha"] == pr["head"]["sha"] and
                len(commits[0]["parents"]) == 1 and
                f"Candidate: `{pr['head']['sha']}`" in (pr.get("body") or ""),
                "older maintenance PR was modified; owner review is required before replacing it")
        api.request("PATCH", f"/repos/{REPOSITORY}/pulls/{pr['number']}", {"state": "closed"})


def publish(args):
    policy, _ = load_policy(args.trusted)
    api = github()
    bundle = read_json(args.bundle)
    base = sha(bundle["base"])
    require(base == os.environ["M_BASE"], "generation artifact has a different base")
    require(api.get(f"/repos/{REPOSITORY}/git/ref/heads/main")["object"]["sha"] == base, "base advanced before publication")
    if bundle.get("noop") is True:
        require(bundle.get("files") == [], "invalid no-op artifact")
        atomic_json(args.output, {"schema": 1, "base": base, "noop": True})
        return
    items = bundle["files"]
    require(isinstance(items, list) and 0 < len(items) <= policy["max_changed_files"], "invalid candidate artifact")
    before, after = {}, {}
    for item in items:
        path = safe_path(item["path"])
        require(path not in after, "duplicate candidate file")
        before[path] = api.file(path, base)
        require(digest(before[path]) == item["before_sha256"], "candidate before content changed")
        after[path] = base64.b64decode(item["content_base64"], validate=True)

    def previous(path):
        if path not in before:
            before[path] = api.file(path, base)
        return before[path]

    check_contents(policy, list(after), previous, lambda path: after.get(path, previous(path)))
    base_commit = api.get(f"/repos/{REPOSITORY}/git/commits/{base}")
    tree_entries = []
    for path, content in after.items():
        blob = api.post(f"/repos/{REPOSITORY}/git/blobs", {"content": base64.b64encode(content).decode(), "encoding": "base64"})
        tree_entries.append({"path": path, "mode": "100644", "type": "blob", "sha": blob["sha"]})
    tree = api.post(f"/repos/{REPOSITORY}/git/trees", {"base_tree": base_commit["tree"]["sha"], "tree": tree_entries})
    branch = policy["branch_prefix"] + base[:12] + "-" + digest(dumps(bundle).encode())[:12]
    refs = api.get(f"/repos/{REPOSITORY}/git/matching-refs/heads/{branch}")
    exact = [ref for ref in refs if ref["ref"] == "refs/heads/" + branch]
    require(len(exact) <= 1, "ambiguous maintenance branch")
    if exact:
        head = exact[0]["object"]["sha"]
        existing = api.get(f"/repos/{REPOSITORY}/git/commits/{head}")
        require(existing["tree"]["sha"] == tree["sha"] and [p["sha"] for p in existing["parents"]] == [base],
                "maintenance branch changed; it will not be overwritten")
    else:
        commit = api.post(f"/repos/{REPOSITORY}/git/commits", {
            "message": "chore(deps): update flake inputs and enrolled packages",
            "tree": tree["sha"], "parents": [base],
        })
        head = commit["sha"]
        api.post(f"/repos/{REPOSITORY}/git/refs", {"ref": "refs/heads/" + branch, "sha": head})
    pulls = api.get(f"/repos/{REPOSITORY}/pulls?state=all&head=averagechris:{branch}")
    require(len(pulls) <= 1, "ambiguous maintenance PR")
    if pulls:
        pr = pulls[0]
        require(pr["state"] == "open" and pr["user"]["login"] == os.environ.get("MAINTENANCE_APP_LOGIN"),
                "existing maintenance PR is closed or has a different author")
    else:
        pr = api.post(f"/repos/{REPOSITORY}/pulls", {
            "head": branch, "base": "main", "title": "chore(deps): update flake inputs and enrolled packages",
            "body": "Coordinated dependency update prepared from current main.\n\n"
                    "Native validation and the task-specific Sol review must both pass before autonomous merging. "
                    "Temporary holds are checked against the policy on the base commit.\n\n"
                    f"Base: `{base}`\nCandidate: `{head}`",
        })
    result = {"schema": 1, "base": base, "head": head, "pr": pr["number"], "noop": False}
    close_superseded(api, policy, pr["number"], os.environ["MAINTENANCE_APP_LOGIN"])
    atomic_json(args.output, result)
    api.post(f"/repos/{REPOSITORY}/actions/workflows/maintenance-validate.yml/dispatches", {
        "ref": "main", "inputs": {"base": base, "head": head, "pr": str(pr["number"])},
    })


def collect(args):
    policy, _ = load_policy(args.trusted)
    expected = read_json(args.identity)
    shards = [read_json(p) for p in sorted(Path(args.shards).glob("*/evidence.json"))]
    evidence = {**expected, "run_id": int(os.environ["GITHUB_RUN_ID"]), "created_at": int(time.time()), "shards": shards}
    atomic_json(args.output, evidence)
    gate.verify_shards(policy, expected, shards)


def decide(args):
    policy, policy_hash = load_policy(args.trusted)
    decision = read_json(args.review)
    require(os.environ.get("GITHUB_ACTOR") == os.environ.get("MAINTENANCE_APP_LOGIN") and
            os.environ.get("MAINTENANCE_APP_LOGIN", "").endswith("[bot]"), "decision did not come from the maintenance App")
    expected = gate.identity(policy_hash, decision["pr"], decision["base"], decision["head"])
    api = github()
    # Published record is useful even when the gate rejects. No candidate code runs here.
    try:
        result = gate.merge(api, policy, expected, decision, decision["evidence_run_id"],
                            os.environ["MAINTENANCE_APP_LOGIN"], os.environ.get("MAINTENANCE_AUTOMERGE") == "true",
                            attestor_login=os.environ.get("MAINTENANCE_HOST_ATTESTOR_LOGIN"))
    except Blocked as error:
        atomic_json(args.output, {**expected, "status": "uncertain" if isinstance(error, gate.MergeUncertain) else "blocked", "summary": str(error)})
        raise
    atomic_json(args.output, {**expected, "status": "merged", "merge_sha": result["sha"]})


def owner_request(args):
    root = Path(args.requests)
    require(root.is_dir(), "maintenance is not enabled on this host")
    if args.operation == "status":
        status = read_json(root / "status.json") if (root / "status.json").exists() else {"phase": "not_started"}
        print(dumps(status))
        return
    atomic_json(root / "request.json", {"id": uuid.uuid4().hex, "operation": args.operation, "created_at": int(time.time())})
    (root / "request.json").chmod(0o660)
    print("Maintenance request recorded.")


def tick(args):
    from maintenance.controller import controller_api, issue, tick as controller_tick
    try:
        api = controller_api(args.app_id, args.installation_id, args.app_login)
        result = controller_tick(args.state, api, args.app_login,
                                 credential("openai-api-key"), args.requests, attestor_login=args.attestor_login)
        print(dumps({"phase": result["phase"]}))
    except (Blocked, OSError, ValueError, KeyError):
        # Includes credential/auth failure before a review/job can be created.
        issue(args.state, {}, "failed", "Maintenance could not start. Check its credentials and service logs; no merge was requested.")
        raise Blocked("maintenance startup failed; an owner alert was queued") from None


def watchdog(args):
    api = github()
    runs = api.get(f"/repos/{REPOSITORY}/actions/workflows/maintenance-heartbeat.yml/runs?event=workflow_dispatch&status=success&per_page=1")["workflow_runs"]
    healthy = False
    if runs:
        import datetime
        run = runs[0]
        stamp = datetime.datetime.fromisoformat(run["created_at"].replace("Z", "+00:00")).timestamp()
        healthy = run.get("conclusion") == "success" and time.time() - stamp < 18 * 3600
    require(healthy, "Michi maintenance heartbeat is missing or stale; Thorny may be unavailable")


def attest(args):
    expected = read_json(args.identity)
    require(sys.platform == "darwin", "macos-keychain attestation must run on suremac")
    host = socket.gethostname().split(".")[0]
    require(host == "suremac", "host attestation must run on suremac")
    policy, _ = load_policy(args.trusted)
    hold = policy["holds"]["emudhra"]
    curl = Path(args.curl)
    resolved_curl = curl.resolve()
    require(curl.is_absolute() and str(curl).startswith("/nix/store/") and ".." not in curl.parts and
            str(resolved_curl).startswith("/nix/store/") and resolved_curl.is_file() and os.access(resolved_curl, os.X_OK),
            "attestor curl must be an executable immutable Nix-store path")
    version = subprocess.run([str(resolved_curl), "--version"], capture_output=True, text=True, timeout=15,
                             env={"PATH": os.defpath, "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8"})
    require(version.returncode == 0 and re.search(r"libcurl/[^\s]+\s+OpenSSL/", version.stdout),
            "attestor curl must use the OpenSSL TLS backend")
    results = []
    for bundle_id, bundle in (("system", "/etc/ssl/certs/ca-certificates.crt"), ("keychain", "/etc/nix/macos-keychain.crt")):
        require(Path(bundle).is_file(), "a required host certificate bundle is missing")
        for endpoint, exit_code in [(hold["healthy_endpoint"], 0)] + [(url, 60) for url in hold["reject_endpoints"]]:
            result = subprocess.run([str(resolved_curl), "--disable", "--silent", "--show-error", "--output", "/dev/null", "--max-time", "30", "--cacert", bundle, endpoint],
                                    capture_output=True, timeout=40,
                                    env={"PATH": os.defpath, "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8"})
            require(result.returncode == exit_code, "host certificate rejection or positive control failed")
            results.append({"bundle": bundle_id, "bundle_sha256": digest(Path(bundle).read_bytes()), "endpoint": endpoint, "exit_code": result.returncode})
    atomic_json(args.output, {**expected, "host": "suremac", "check": "macos-keychain", "status": "passed",
                              "created_at": int(time.time()), "checks": results})


def accept_attestation(args):
    policy, policy_hash = load_policy(args.trusted)
    expected = read_json(args.identity)
    require(expected["policy_sha256"] == policy_hash, "host attestation policy changed")
    require(os.environ.get("MAINTENANCE_HOST_ATTESTOR_LOGIN") and
            os.environ.get("GITHUB_ACTOR") == os.environ["MAINTENANCE_HOST_ATTESTOR_LOGIN"],
            "host attestation sender is not authorized")
    value = read_json(args.attestation)
    gate.verify_identity(value, expected)
    gate.fresh(value.get("created_at"), policy["max_evidence_age_seconds"], time.time())
    require(value.get("host") == "suremac" and value.get("check") == "macos-keychain" and
            value.get("status") == "passed", "host attestation did not pass")
    checks = value.get("checks", [])
    hold = policy["holds"]["emudhra"]
    endpoints = {hold["healthy_endpoint"]: 0, **{url: 60 for url in hold["reject_endpoints"]}}
    # Separate slots remain distinguishable even when their bundle bytes match.
    required_pairs = {(slot, endpoint) for slot in ("system", "keychain") for endpoint in endpoints}
    actual_pairs = [(row.get("bundle"), row.get("endpoint")) for row in checks]
    require(len(actual_pairs) == len(required_pairs) and set(actual_pairs) == required_pairs and
            all(isinstance(x.get("bundle_sha256"), str) and re.fullmatch(r"[0-9a-f]{64}", x["bundle_sha256"]) for x in checks),
            "host attestation has incomplete bundle evidence")
    for slot in ("system", "keychain"):
        require(len({row["bundle_sha256"] for row in checks if row["bundle"] == slot}) == 1,
                "host bundle changed during certificate probes")
    require(all(x.get("endpoint") in endpoints and x.get("exit_code") == endpoints[x["endpoint"]] for x in checks),
            "host certificate probe failed")
    atomic_json(args.output, value)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("prepare", "publish", "collect", "decide", "attest", "accept-attestation"):
        p = commands.add_parser(name)
        p.add_argument("--trusted", type=Path, required=True)
        p.add_argument("--output", type=Path, required=True)
        if name in {"collect", "attest", "accept-attestation"}:
            p.add_argument("--identity", type=Path, required=True)
        if name == "publish":
            p.add_argument("--bundle", type=Path, required=True)
        if name == "collect":
            p.add_argument("--shards", type=Path, required=True)
        if name == "decide":
            p.add_argument("--review", type=Path, required=True)
        if name == "accept-attestation":
            p.add_argument("--attestation", type=Path, required=True)
        if name == "attest":
            p.add_argument("--curl", required=True)
    p = commands.add_parser("request")
    p.add_argument("operation", choices=("run", "pause", "resume", "status"))
    p.add_argument("--requests", type=Path, required=True)
    p = commands.add_parser("tick")
    p.add_argument("--state", type=Path, required=True)
    p.add_argument("--requests", type=Path, required=True)
    p.add_argument("--app-login", required=True)
    p.add_argument("--app-id", required=True)
    p.add_argument("--installation-id", required=True)
    p.add_argument("--attestor-login", default="")
    commands.add_parser("watchdog")
    args = parser.parse_args()
    functions = {"prepare": prepare, "publish": publish, "collect": collect, "decide": decide,
                 "request": owner_request, "tick": tick, "watchdog": watchdog, "attest": attest,
                 "accept-attestation": accept_attestation}
    try:
        functions[args.command](args)
    except (Blocked, ValueError, KeyError, OSError) as error:
        print("maintenance blocked: " + (str(error) if isinstance(error, Blocked) else "invalid or unavailable input"), file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
