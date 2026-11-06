"""GitHub independently verifies candidate identity, evidence provenance, and policy."""
from __future__ import annotations

import time
import fnmatch
import datetime
import re
import urllib.parse

from maintenance.common import Blocked, REPOSITORY, digest, dumps, require, sha
from maintenance.policy import check_contents

VALIDATION_CONTEXT = "Maintenance / native evidence"


class MergeUncertain(Blocked):
    pass


def identity(policy_hash, pr, base, head):
    require(isinstance(pr, int) and not isinstance(pr, bool) and pr > 0, "invalid PR number")
    return {"schema": 1, "repository": REPOSITORY, "pr": pr, "base": sha(base),
            "head": sha(head), "policy_sha256": policy_hash}


def verify_identity(value, expected):
    require(all(value.get(k) == v for k, v in expected.items()), "evidence identifies a different candidate or policy")


def verify_control_run(run, path, base, app_login):
    require(run.get("event") == "workflow_dispatch" and run.get("path") == path and
            run.get("head_sha") == base and run.get("head_branch") == "main" and
            run.get("head_repository", {}).get("full_name") == REPOSITORY and
            run.get("actor", {}).get("login") == app_login,
            "control workflow result has untrusted provenance")


def fresh(timestamp, limit, now):
    require(isinstance(timestamp, (float, int)) and not isinstance(timestamp, bool) and
            now - limit <= timestamp <= now + 60, "evidence is stale or from the future")


def verify_pr(api, policy, expected, app_login):
    require(app_login and app_login.endswith("[bot]"), "maintenance GitHub App identity is not configured")
    pr = api.get(f"/repos/{REPOSITORY}/pulls/{expected['pr']}")
    current = api.get(f"/repos/{REPOSITORY}/git/ref/heads/{policy['base_branch']}")["object"]["sha"]
    require(current == expected["base"], "base advanced; regenerate candidate and evidence")
    require(pr["state"] == "open" and not pr["draft"] and pr["user"]["login"] == app_login,
            "PR is not an eligible maintenance App candidate")
    require(pr["head"]["repo"]["full_name"] == REPOSITORY and
            pr["base"]["repo"]["full_name"] == REPOSITORY and
            pr["base"]["ref"] == policy["base_branch"] and
            pr["base"]["sha"] == expected["base"] and pr["head"]["sha"] == expected["head"] and
            pr["head"]["ref"].startswith(policy["branch_prefix"]), "PR identity changed")
    commits = api.pages(f"/repos/{REPOSITORY}/pulls/{expected['pr']}/commits")
    require(len(commits) == 1 and commits[0]["sha"] == expected["head"] and
            [p["sha"] for p in commits[0]["parents"]] == [expected["base"]],
            "maintenance candidate must be one commit on the tested base")
    return pr


def verify_sources(api, policy, expected):
    files = api.pages(f"/repos/{REPOSITORY}/pulls/{expected['pr']}/files")
    require(all(x["status"] == "modified" and isinstance(x.get("patch"), str) for x in files),
            "candidate contains added, deleted, renamed, binary, or unreviewable files")
    require(sum(len(x["patch"].encode()) for x in files) <= policy["max_patch_bytes"], "candidate patch exceeds review budget")
    tree = api.get(f"/repos/{REPOSITORY}/git/trees/{expected['head']}?recursive=1")
    require(not tree.get("truncated"), "candidate tree was truncated")
    modes = {x["path"]: x["mode"] for x in tree["tree"]}
    names = [x["filename"] for x in files]
    require(all(modes.get(x) == "100644" for x in names), "candidate changes file type or executable mode")
    cache = {}

    def content(path, ref):
        key = (path, ref)
        if key not in cache:
            cache[key] = api.file(path, ref)
        return cache[key]

    result = check_contents(policy, names, lambda p: content(p, expected["base"]),
                            lambda p: content(p, expected["head"]))
    result["patches"] = [{"path": x["filename"], "patch": x["patch"]} for x in files]
    result["releases"] = []
    packages = [p for p in names if p in policy["manual_packages"]]
    if packages:
        import json
        manifest = json.loads(content("manual-package-updates.json", expected["base"]))
        for path in packages:
            matches = [p for p in manifest["packages"] if p["file"] == path and p["enabled"]]
            require(len(matches) == 1 and matches[0]["latest"]["kind"] == "github-release", "package is not enrolled in automatic releases")
            package = matches[0]
            match = re.search(rb'\bversion\s*=\s*"([^"]+)"', content(path, expected["head"]))
            require(match, "package version is missing")
            version = match[1].decode()
            old_version = re.search(rb'\bversion\s*=\s*"([^"]+)"', content(path, expected["base"]))
            require(old_version and re.fullmatch(r"\d+(?:\.\d+)+", version) and
                    tuple(map(int, version.split("."))) > tuple(map(int, old_version[1].decode().split("."))),
                    "manual package update must advance its version; same-version asset changes require review")
            latest = package["latest"]
            tag = latest.get("stripPrefix", "") + version
            release = api.get(f"/repos/{latest['owner']}/{latest['repo']}/releases/tags/{urllib.parse.quote(tag, safe='')}")
            require(not release.get("draft") and not release.get("prerelease"), "package release is draft or prerelease")
            stamp = datetime.datetime.fromisoformat(release["published_at"].replace("Z", "+00:00")).timestamp()
            cooldown = package.get("cooldownDays", policy["cooldown_days"]) if package.get("cooldown") else 0
            require(stamp <= time.time() - cooldown * 86400, "package release has not passed its cooldown")
            assets = {asset.get("browser_download_url"): asset for asset in release.get("assets", [])}
            for asset in package["assets"]:
                url = asset["url"].replace("{version}", version)
                require(url in assets, "enrolled release asset is missing")
                modified = datetime.datetime.fromisoformat(assets[url]["updated_at"].replace("Z", "+00:00")).timestamp()
                require(modified <= time.time() - cooldown * 86400, "release asset changed inside its cooldown")
            result["releases"].append({"package": package["name"], "version": version, "url": release["html_url"],
                                       "published_at": release["published_at"], "notes": release.get("body", "")})
    return result


def verify_shards(policy, expected, shards, now=None):
    now = time.time() if now is None else now
    require(isinstance(shards, list) and len(shards) == len(policy["required_systems"]), "incomplete native evidence")
    by_system = {}
    for shard in shards:
        verify_identity(shard, expected)
        fresh(shard.get("created_at"), policy["max_evidence_age_seconds"], now)
        system = shard.get("system")
        require(system in policy["required_systems"] and system not in by_system, "duplicate or unexpected native platform")
        require(shard.get("status") == "passed" and shard.get("commands") and
                all(x.get("exit_code") == x.get("expected_exit_code", 0) for x in shard["commands"]),
                "native checks failed or did not run")
        by_system[system] = shard
    return by_system


def verify_validation(api, policy, expected, run_id, now=None):
    run = api.get(f"/repos/{REPOSITORY}/actions/runs/{int(run_id)}")
    require(run.get("event") == "workflow_dispatch" and run.get("path") == policy["validation_workflow"] and
            run.get("head_sha") == expected["base"] and run.get("head_branch") == policy["base_branch"] and
            run.get("head_repository", {}).get("full_name") == REPOSITORY and
            run.get("status") == "completed" and run.get("conclusion") == "success",
            "validation run did not pass on trusted base workflow")
    evidence = api.artifact(int(run_id), "maintenance-evidence")
    verify_identity(evidence, expected)
    verify_shards(policy, expected, evidence.get("shards"), now)
    require(evidence.get("run_id") == int(run_id), "evidence run id mismatch")
    return evidence


def attach_host_attestation(api, policy, expected, evidence, run_id, attestor_login, now=None):
    """Only a separately authorized attestor's trusted workflow can supply host facts."""
    require(attestor_login, "host attestor identity is not configured")
    run = api.get(f"/repos/{REPOSITORY}/actions/runs/{int(run_id)}")
    require(run.get("event") == "workflow_dispatch" and run.get("path") == ".github/workflows/maintenance-attest.yml" and
            run.get("head_sha") == expected["base"] and run.get("head_branch") == "main" and
            run.get("actor", {}).get("login") == attestor_login and run.get("conclusion") == "success",
            "host attestation did not come from the authorized trusted workflow")
    attestation = api.artifact(int(run_id), "maintenance-host-attestation")
    verify_identity(attestation, expected)
    fresh(attestation.get("created_at"), policy["max_evidence_age_seconds"], time.time() if now is None else now)
    require(attestation.get("status") == "passed" and attestation.get("host") == "suremac" and
            attestation.get("check") == "macos-keychain", "invalid host certificate attestation")
    result = dict(evidence)
    result["host_attestation_run_id"] = int(run_id)
    result["host_attestations"] = {"macos-keychain": attestation}
    return result


def verify_review(policy, expected, review, evidence, nixpkgs, now=None):
    now = time.time() if now is None else now
    verify_identity(review, expected)
    fresh(review.get("created_at"), policy["max_review_age_seconds"], now)
    require(review.get("model") == policy["model"] and review.get("reasoning") == policy["reasoning"], "review model changed")
    require(review.get("evidence_run_id") == evidence["run_id"] and
            review.get("evidence_sha256") == digest(dumps(evidence).encode()), "review is not bound to verified evidence")
    require(review.get("decision") == "merge" and isinstance(review.get("summary"), str) and
            review["summary"].strip() and review.get("unresolved") == [], "review did not approve this candidate")
    shards = verify_shards(policy, expected, evidence["shards"], now)
    decisions = review.get("holds", {})
    require(set(decisions) == set(policy["holds"]), "hold review is incomplete")
    for name, hold in policy["holds"].items():
        decision = decisions[name]
        require(isinstance(decision.get("rationale"), str) and decision["rationale"].strip(), "hold rationale missing")
        if nixpkgs == hold["revision"]:
            require(decision.get("decision") == "retain", "unchanged hold was not retained")
            continue
        require(decision.get("decision") == "release" and decision.get("sources"), "hold release lacks reasoned evidence")
        for shard in shards.values():
            checks = shard.get("holds", {}).get(name, {})
            required = hold["required_checks"]
            if shard["system"].endswith("darwin"):
                required = [key for key in required if key != "system-bundle"]
            require(all(checks.get(key) is True for key in required), f"{name} exit conditions did not pass")
        if hold.get("requires_host_attestation"):
            attestation = evidence.get("host_attestations", {}).get(hold["host_attestation_check"], {})
            verify_identity(attestation, expected)
            fresh(attestation.get("created_at"), policy["max_evidence_age_seconds"], now)
            require(attestation.get("status") == "passed" and attestation.get("host") == "suremac",
                    "required macOS host attestation is missing")


def verify_repository_gates(api):
    # The trusted workflow supplies the same App ID it passed to token minting.
    app_id = getattr(api, "app_id", None)
    require(isinstance(app_id, int) and not isinstance(app_id, bool) and app_id > 0,
            "maintenance GitHub App installation identity is unavailable")
    rules = api.get(f"/repos/{REPOSITORY}/rules/branches/main")
    checks = [r.get("parameters", {}) for r in rules if r.get("type") == "required_status_checks"]
    require(any(r.get("strict_required_status_checks_policy") is True and
                any(x.get("context") == VALIDATION_CONTEXT for x in r.get("required_status_checks", []))
                for r in checks), "strict required maintenance status check is not configured")
    require(any(r.get("type") == "pull_request" for r in rules), "main does not require pull requests")
    rulesets = api.pages(f"/repos/{REPOSITORY}/rulesets?includes_parents=true")
    for summary in rulesets:
        if summary.get("enforcement") != "active" or summary.get("target") != "branch":
            continue
        detail = api.get(f"/repos/{REPOSITORY}/rulesets/{summary['id']}")
        conditions = detail.get("conditions", {}).get("ref_name", {})
        includes = conditions.get("include", [])
        excludes = conditions.get("exclude", [])
        matches = lambda pattern: pattern in {"~ALL", "~DEFAULT_BRANCH"} or fnmatch.fnmatchcase("refs/heads/main", pattern)
        if not any(matches(pattern) for pattern in includes) or any(matches(pattern) for pattern in excludes):
            continue
        require(not any(actor.get("actor_type") == "Integration" and actor.get("actor_id") == app_id
                        for actor in detail.get("bypass_actors", [])),
                "maintenance GitHub App can bypass protected main rules")


def merge(api, policy, expected, review, run_id, app_login, enabled, now=None, attestor_login=None):
    require(policy.get("merge_enabled") is True and enabled is True, "autonomous merging is disabled")
    verify_repository_gates(api)
    verify_pr(api, policy, expected, app_login)
    sources = verify_sources(api, policy, expected)
    evidence = verify_validation(api, policy, expected, run_id, now)
    if review.get("host_attestation_run_id"):
        evidence = attach_host_attestation(api, policy, expected, evidence, review["host_attestation_run_id"], attestor_login, now)
    verify_review(policy, expected, review, evidence, sources["nixpkgs"], now)
    # Recheck after network I/O. Strict server-side checks close the base race.
    verify_pr(api, policy, expected, app_login)
    try:
        result = api.request("PUT", f"/repos/{REPOSITORY}/pulls/{expected['pr']}/merge",
                             {"sha": expected["head"], "merge_method": "squash"})
    except Blocked:
        raise MergeUncertain("merge request outcome is uncertain; reconcile the PR before retrying") from None
    require(result.get("merged") is True, "GitHub refused the exact candidate merge")
    return result
