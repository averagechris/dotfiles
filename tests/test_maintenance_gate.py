"""Fail-closed tests for GitHub's final maintenance merge gate."""
from __future__ import annotations

import copy
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from maintenance.common import Blocked, REPOSITORY, digest, dumps
from maintenance import gate

BASE, HEAD = "a" * 40, "b" * 40
NOW = 2_000_000_000
APP = "maintenance[bot]"


def fixture():
    policy = {
        "merge_enabled": True, "base_branch": "main", "branch_prefix": "maintenance/",
        "max_patch_bytes": 10000, "validation_workflow": ".github/workflows/maintenance.yml",
        "required_systems": ["x86_64-linux", "aarch64-darwin"], "max_evidence_age_seconds": 3600,
        "max_review_age_seconds": 3600, "model": "review-model", "reasoning": "high",
        "holds": {"darwin": {"revision": "old", "required_checks": ["build"],
                               "requires_host_attestation": True,
                               "host_attestation_check": "native"}},
    }
    expected = gate.identity("policy-hash", 7, BASE, HEAD)
    shards = [
        {**expected, "system": system, "status": "passed", "created_at": NOW,
         "commands": [{"exit_code": 0}], "holds": {"darwin": {"build": True}}}
        for system in policy["required_systems"]
    ]
    attestation = {**expected, "created_at": NOW, "status": "passed", "host": "suremac"}
    evidence = {**expected, "run_id": 91, "shards": shards, "host_attestations": {"native": attestation}}
    review = {**expected, "created_at": NOW, "model": policy["model"], "reasoning": policy["reasoning"],
              "evidence_run_id": 91, "evidence_sha256": digest(dumps(evidence).encode()),
              "decision": "merge", "summary": "Reviewed candidate", "unresolved": [],
              "holds": {"darwin": {"decision": "retain", "rationale": "Still required."}}}
    return policy, expected, evidence, review


class FakeGitHub:
    def __init__(self):
        self.merge_calls = []
        self.app_id = 456
        self.current_base = BASE
        self.pr = {"state": "open", "draft": False, "user": {"login": APP},
                   "head": {"repo": {"full_name": REPOSITORY}, "sha": HEAD, "ref": "maintenance/7"},
                   "base": {"repo": {"full_name": REPOSITORY}, "ref": "main", "sha": BASE}}
        self.commit = {"sha": HEAD, "parents": [{"sha": BASE}]}
        self.rules = [
            {"type": "required_status_checks", "parameters": {
                "strict_required_status_checks_policy": True,
                "required_status_checks": [{"context": gate.VALIDATION_CONTEXT}]}},
            {"type": "pull_request"},
        ]
        self.rulesets = [{"id": 30, "target": "branch", "enforcement": "active"}]
        self.ruleset_details = {30: {"conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
                                     "bypass_actors": [{"actor_type": "User", "actor_id": 123}]}}

    def get(self, path):
        if path.endswith("/rulesets?includes_parents=true"):
            return self.rulesets
        if "/rulesets/" in path:
            return self.ruleset_details[int(path.rsplit("/", 1)[1])]
        if "/rules/branches/" in path:
            return self.rules
        if "/git/ref/heads/" in path:
            return {"object": {"sha": self.current_base}}
        if "/pulls/7" in path:
            return self.pr
        raise AssertionError(f"unexpected GET {path}")

    def pages(self, path):
        if path.endswith("/rulesets?includes_parents=true"):
            return self.rulesets
        if path.endswith("/commits"):
            return [self.commit]
        raise AssertionError(f"unexpected pages {path}")

    def request(self, method, path, payload=None):
        self.merge_calls.append((method, path, payload))
        return {"merged": True, "sha": HEAD}


class MergeGateTests(unittest.TestCase):
    def setUp(self):
        self.policy, self.expected, self.evidence, self.review = fixture()
        self.api = FakeGitHub()

    def merge(self, **kwargs):
        # Stub only content/artifact parsing here; API identity, protected branch
        # rules, and the final exact-SHA request remain real.
        enabled = kwargs.pop("enabled", True)
        with mock.patch.object(gate, "verify_sources", return_value={"nixpkgs": "old"}), \
             mock.patch.object(gate, "verify_validation", return_value=self.evidence), \
             mock.patch.object(gate, "verify_review"):
            return gate.merge(self.api, self.policy, self.expected, self.review, 91, APP, enabled,
                              now=NOW, **kwargs)

    def rejected(self, **kwargs):
        with self.assertRaises(Blocked):
            self.merge(**kwargs)
        self.assertEqual(self.api.merge_calls, [])

    def test_disabled_policy_or_flag_fails_closed(self):
        self.policy["merge_enabled"] = False
        self.rejected()
        self.policy["merge_enabled"] = True
        self.rejected(enabled=False)

    def test_repository_rule_must_be_strict_and_require_status(self):
        self.api.rules[0]["parameters"]["strict_required_status_checks_policy"] = False
        self.rejected()

    def test_active_main_ruleset_does_not_allow_maintenance_app_bypass(self):
        self.api.ruleset_details[30]["bypass_actors"] = [{"actor_type": "Integration", "actor_id": 456}]
        self.rejected()

    def test_ruleset_bypass_exclusions_and_nonmatching_patterns_are_ignored(self):
        self.api.ruleset_details[30] = {
            "conditions": {"ref_name": {"include": ["release/*"], "exclude": []}},
            "bypass_actors": [{"actor_type": "Integration", "actor_id": 456}],
        }
        gate.verify_repository_gates(self.api)
        self.api.ruleset_details[30] = {
            "conditions": {"ref_name": {"include": ["~ALL"], "exclude": ["refs/heads/main"]}},
            "bypass_actors": [{"actor_type": "Integration", "actor_id": 456}],
        }
        gate.verify_repository_gates(self.api)
        self.api.ruleset_details[30] = {
            "conditions": {"ref_name": {"include": ["refs/heads/main"], "exclude": []}},
            "bypass_actors": [{"actor_type": "Integration", "actor_id": 456}],
        }
        self.rejected()
        self.api.rules[0]["parameters"]["strict_required_status_checks_policy"] = True
        self.api.rules[0]["parameters"]["required_status_checks"] = []
        self.rejected()

    def test_wrong_author_fork_head_base_and_branch_are_rejected(self):
        for change in (
            lambda: self.api.pr["user"].update(login="someone-else"),
            lambda: self.api.pr["head"]["repo"].update(full_name="fork/repo"),
            lambda: self.api.pr["head"].update(sha="c" * 40),
            lambda: self.api.pr["base"].update(sha="c" * 40),
            lambda: self.api.pr["head"].update(ref="feature/7"),
        ):
            self.api = FakeGitHub()
            change()
            self.rejected()

    def test_multi_commit_or_wrong_parent_is_rejected(self):
        for commits in ([self.api.commit, {"sha": "c" * 40, "parents": [{"sha": HEAD}]}],
                        [{"sha": HEAD, "parents": [{"sha": "c" * 40}]}]):
            self.api = FakeGitHub()
            with mock.patch.object(gate, "verify_sources", return_value={"nixpkgs": "old"}), \
                 mock.patch.object(gate, "verify_validation", return_value=self.evidence), \
                 mock.patch.object(gate, "verify_review"), \
                 mock.patch.object(self.api, "pages", return_value=commits):
                with self.assertRaises(Blocked):
                    gate.merge(self.api, self.policy, self.expected, self.review, 91, APP, True, now=NOW)
            self.assertEqual(self.api.merge_calls, [])

    def test_base_advance_at_last_check_and_github_refusal_block_merge(self):
        original = gate.verify_pr
        calls = 0

        def advance_on_second(api, policy, expected, app):
            nonlocal calls
            calls += 1
            if calls == 2:
                api.current_base = "c" * 40
            return original(api, policy, expected, app)

        with mock.patch.object(gate, "verify_sources", return_value={"nixpkgs": "old"}), \
             mock.patch.object(gate, "verify_validation", return_value=self.evidence), \
             mock.patch.object(gate, "verify_review"), mock.patch.object(gate, "verify_pr", side_effect=advance_on_second):
            with self.assertRaises(Blocked):
                gate.merge(self.api, self.policy, self.expected, self.review, 91, APP, True, now=NOW)
        self.assertEqual(self.api.merge_calls, [])
        self.api = FakeGitHub()
        with mock.patch.object(self.api, "request", return_value={"merged": False}):
            self.rejected()


class EvidenceGateTests(unittest.TestCase):
    def setUp(self):
        self.policy, self.expected, self.evidence, self.review = fixture()

    def test_missing_duplicate_failed_and_stale_native_evidence(self):
        shards = self.evidence["shards"]
        for invalid in (shards[:1], [shards[0], shards[0]],
                        [{**shards[0], "status": "failed"}, shards[1]],
                        [{**shards[0], "created_at": NOW - 4000}, shards[1]]):
            with self.subTest(evidence=invalid), self.assertRaises(Blocked):
                gate.verify_shards(self.policy, self.expected, invalid, NOW)

    def test_evidence_identity_and_command_failures_are_rejected(self):
        for shard in ([{**self.evidence["shards"][0], "head": "c" * 40}, self.evidence["shards"][1]],
                      [{**self.evidence["shards"][0], "commands": [{"exit_code": 1}]}, self.evidence["shards"][1]]):
            with self.subTest(shard=shard), self.assertRaises(Blocked):
                gate.verify_shards(self.policy, self.expected, shard, NOW)

    def test_model_evidence_hash_unresolved_and_hold_decisions_are_bound(self):
        with self.assertRaises(Blocked):
            gate.verify_review(self.policy, self.expected, {**self.review, "model": "other"}, self.evidence, "old", NOW)
        with self.assertRaises(Blocked):
            gate.verify_review(self.policy, self.expected, {**self.review, "evidence_sha256": "0" * 64}, self.evidence, "old", NOW)
        with self.assertRaises(Blocked):
            gate.verify_review(self.policy, self.expected, {**self.review, "unresolved": ["check"]}, self.evidence, "old", NOW)
        with self.assertRaises(Blocked):
            gate.verify_review(self.policy, self.expected,
                               {**self.review, "holds": {"darwin": {"decision": "release", "rationale": "x", "sources": ["log"]}}},
                               self.evidence, "old", NOW)

    def test_conditional_release_requires_all_platform_checks_and_host_attestation(self):
        self.review["holds"]["darwin"] = {"decision": "release", "rationale": "Exit checks passed.", "sources": ["build log"]}
        gate.verify_review(self.policy, self.expected, self.review, self.evidence, "new", NOW)
        no_attestation = copy.deepcopy(self.evidence)
        no_attestation["host_attestations"] = {}
        review = {**self.review, "evidence_sha256": digest(dumps(no_attestation).encode())}
        with self.assertRaises(Blocked):
            gate.verify_review(self.policy, self.expected, review, no_attestation, "new", NOW)
        failed_check = copy.deepcopy(self.evidence)
        failed_check["shards"][0]["holds"]["darwin"]["build"] = False
        review = {**self.review, "evidence_sha256": digest(dumps(failed_check).encode())}
        with self.assertRaises(Blocked):
            gate.verify_review(self.policy, self.expected, review, failed_check, "new", NOW)

    def test_validation_requires_trusted_workflow_run_and_unexpired_artifact(self):
        class API:
            run = {"event": "workflow_dispatch", "path": self.policy["validation_workflow"],
                   "head_sha": BASE, "head_branch": "main", "head_repository": {"full_name": REPOSITORY},
                   "status": "completed", "conclusion": "success"}
            evidence = self.evidence

            def get(inner, path):
                return inner.run

            def artifact(inner, run_id, name):
                return inner.evidence

        api = API()
        self.assertEqual(gate.verify_validation(api, self.policy, self.expected, 91, NOW), self.evidence)
        for field, value in (("event", "pull_request"), ("head_sha", "c" * 40),
                             ("head_repository", {"full_name": "fork/repo"}), ("conclusion", "failure"),
                             ("path", "attacker.yml"), ("status", "in_progress")):
            api.run = {**API.run, field: value}
            with self.subTest(field=field), self.assertRaises(Blocked):
                gate.verify_validation(api, self.policy, self.expected, 91, NOW)
        api.run = API.run
        api.evidence = {**self.evidence, "run_id": 90}
        with self.assertRaises(Blocked):
            gate.verify_validation(api, self.policy, self.expected, 91, NOW)
        api.evidence = self.evidence

        def expired(*_):
            raise Blocked("expired artifact")
        api.artifact = expired
        with self.assertRaises(Blocked):
            gate.verify_validation(api, self.policy, self.expected, 91, NOW)

    def test_source_status_patch_tree_and_file_modes_fail_closed(self):
        class API:
            files = [{"filename": "flake.lock", "status": "modified", "patch": "diff"}]
            mode = "100644"

            def pages(inner, path):
                return inner.files

            def get(inner, path):
                return {"tree": [{"path": "flake.lock", "mode": inner.mode}]}

            def file(inner, path, ref):
                return b"{}"

        api = API()
        with mock.patch.object(gate, "check_contents", return_value={"nixpkgs": "old"}):
            gate.verify_sources(api, {**self.policy, "canonical_locks": [], "manual_packages": []}, self.expected)
            api.mode = "120000"
            with self.assertRaises(Blocked):
                gate.verify_sources(api, {**self.policy, "canonical_locks": [], "manual_packages": []}, self.expected)
            api.mode = "100644"
            api.files = [{"filename": "flake.lock", "status": "added", "patch": "diff"}]
            with self.assertRaises(Blocked):
                gate.verify_sources(api, {**self.policy, "canonical_locks": [], "manual_packages": []}, self.expected)


if __name__ == "__main__":
    unittest.main()
