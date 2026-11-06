#!/usr/bin/env python3
"""Mocked controller and review tests; no network or model calls are made."""
from __future__ import annotations

import datetime
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from maintenance import cli, controller, gate
from maintenance.common import Blocked, digest, dumps, load_policy
from maintenance.review import review


ROOT = Path(__file__).resolve().parents[1]
BASE = "a" * 40
HEAD = "b" * 40
NOW = 1_800_000_000


class FakeApi:
    def __init__(self, *, base=BASE, runs=None, artifacts=None, post_error=None, fail_path=None, pr=None):
        self.base, self.runs, self.artifacts, self.post_error = base, runs or [], artifacts or {}, post_error
        self.fail_path = fail_path
        self.pr = pr or {"merged": False, "head": {"sha": HEAD}}
        self.calls = []

    def get(self, path):
        self.calls.append(("get", path))
        if path.endswith("/git/ref/heads/main"):
            return {"object": {"sha": self.base}}
        if "/pulls/" in path:
            return self.pr
        raise AssertionError(f"unexpected GET {path}")

    def file(self, path, ref):
        self.calls.append(("file", path, ref))
        return (ROOT / path).read_bytes()

    def pages(self, path, key=None):
        self.calls.append(("pages", path))
        workflow = path.split("/workflows/", 1)[-1].split("/", 1)[0]
        return [{"event": "workflow_dispatch", "path": ".github/workflows/" + workflow,
                 "head_sha": BASE, "head_branch": "main",
                 "head_repository": {"full_name": "averagechris/dotfiles"},
                 "actor": {"login": "michi[bot]"}, **run} for run in self.runs]

    def artifact(self, run_id, name):
        self.calls.append(("artifact", run_id, name))
        return self.artifacts[name]

    def post(self, path, value):
        self.calls.append(("post", path, value))
        if self.post_error and (self.fail_path is None or self.fail_path in path):
            raise self.post_error
        return {}


def state_for(phase, policy_hash, **fields):
    return {"schema": 1, "phase": phase, "base": BASE, "policy_sha256": policy_hash,
            "request_id": "request-1", "started_at": NOW, "last_heartbeat": NOW,
            "last_generation": NOW, **fields}


class ControllerTests(unittest.TestCase):
    def test_control_results_reject_untrusted_provenance(self):
        good = {"event": "workflow_dispatch", "path": ".github/workflows/maintenance-decide.yml",
                "head_sha": BASE, "head_branch": "main",
                "head_repository": {"full_name": "averagechris/dotfiles"}, "actor": {"login": "michi[bot]"}}
        for field, value in (("event", "push"), ("head_sha", HEAD), ("head_branch", "other"),
                             ("actor", {"login": "other"}), ("head_repository", {"full_name": "other/repo"})):
            with self.subTest(field=field), self.assertRaises(Blocked):
                gate.verify_control_run({**good, field: value}, good["path"], BASE, "michi[bot]")

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.state_dir = Path(self.temp.name) / "state"
        self.requests = Path(self.temp.name) / "requests"
        self.requests.mkdir()
        self.policy, self.policy_hash = load_policy(ROOT)

    def tearDown(self):
        self.temp.cleanup()

    def write_state(self, state):
        from maintenance.common import atomic_json
        atomic_json(self.state_dir / "state.json", state)

    def test_paused_controller_keeps_heartbeat_but_skips_generation_and_model(self):
        self.write_state({"schema": 1, "phase": "idle", "paused": True})
        api = FakeApi()
        reviewer = mock.Mock(side_effect=AssertionError("model must not be called"))
        result = controller.tick(self.state_dir, api, "michi[bot]", "key", self.requests,
                                 now=NOW, reviewer=reviewer)
        self.assertTrue(result["paused"])
        dispatches = [x for x in api.calls if x[0] == "post"]
        self.assertEqual(len(dispatches), 1)
        self.assertIn("maintenance-heartbeat.yml", dispatches[0][1])
        reviewer.assert_not_called()

    def test_noop_candidate_completes_without_model_review(self):
        self.write_state(state_for("generating", self.policy_hash))
        title = "Maintenance candidate request-1"
        created = datetime.datetime.fromtimestamp(NOW, datetime.timezone.utc).isoformat()
        api = FakeApi(runs=[{"display_title": title, "created_at": created, "status": "completed",
                             "conclusion": "success", "head_sha": BASE, "id": 7}],
                      artifacts={"maintenance-candidate-result": {"base": BASE, "noop": True}})
        reviewer = mock.Mock(side_effect=AssertionError("no-op must not be reviewed"))
        result = controller.tick(self.state_dir, api, "michi[bot]", "key", self.requests,
                                 now=NOW, reviewer=reviewer)
        self.assertEqual(result["phase"], "complete")
        reviewer.assert_not_called()

    def test_lost_dispatch_is_persisted_and_same_request_is_not_retried(self):
        from maintenance.common import atomic_json
        atomic_json(self.requests / "request.json", {"id": "owner-1", "operation": "run"})
        api = FakeApi(post_error=Blocked("dispatch response lost"), fail_path="maintenance-candidate.yml")
        first = controller.tick(self.state_dir, api, "michi[bot]", "key", self.requests, now=NOW)
        self.assertEqual(first["phase"], "generating")
        dispatches = [x for x in api.calls if x[0] == "post" and "maintenance-candidate.yml" in x[1]]
        self.assertEqual(len(dispatches), 1)
        api.post_error = None
        created = datetime.datetime.fromtimestamp(NOW, datetime.timezone.utc).isoformat()
        api.runs = [{"display_title": "Maintenance candidate " + first["request_id"],
                     "created_at": created, "status": "completed", "conclusion": "success",
                     "head_sha": BASE, "id": 7}]
        api.artifacts["maintenance-candidate-result"] = {"base": BASE, "noop": True}
        second = controller.tick(self.state_dir, api, "michi[bot]", "key", self.requests, now=NOW + 1)
        self.assertEqual(second["phase"], "complete")
        self.assertEqual(len([x for x in api.calls if x[0] == "post" and "maintenance-candidate.yml" in x[1]]), 1)

    def test_lost_decision_dispatch_reconciles_exact_merged_head(self):
        self.write_state(state_for("validating", self.policy_hash, pr=4, head=HEAD))
        title = "Maintenance validation " + HEAD
        created = datetime.datetime.fromtimestamp(NOW, datetime.timezone.utc).isoformat()
        api = FakeApi(runs=[{"display_title": title, "created_at": created, "status": "completed",
                             "conclusion": "success", "head_sha": BASE, "id": 8}],
                      post_error=Blocked("response lost"), fail_path="maintenance-decide.yml")
        decision = {"decision": "merge", "summary": "passed", "unresolved": [], "holds": {}}
        reviewer = mock.Mock(return_value=decision)
        with mock.patch("maintenance.controller.gate.verify_validation", return_value={"run_id": 9}), \
             mock.patch("maintenance.controller.gate.verify_sources", return_value={"nixpkgs": self.policy["holds"]["emudhra"]["revision"]}), \
             mock.patch("maintenance.controller.collect_context", return_value={}), \
             mock.patch("maintenance.controller.gate.verify_review"), \
             mock.patch("maintenance.controller.issue") as alert:
            first = controller.tick(self.state_dir, api, "michi[bot]", "key", self.requests, now=NOW,
                                    reviewer=reviewer)
        self.assertEqual(first["phase"], "deciding", first)
        alert.assert_called_once()
        decide_dispatches = [x for x in api.calls if x[0] == "post" and "maintenance-decide.yml" in x[1]]
        self.assertEqual(len(decide_dispatches), 1)

        api.base = "c" * 40  # main may advance after the exact candidate was merged
        api.post_error = None
        from maintenance.common import atomic_json
        atomic_json(self.requests / "request.json", {"id": "owner-2", "operation": "run"})
        api.runs = [{"display_title": "Maintenance decision " + first["request_id"],
                     "created_at": created, "status": "completed", "conclusion": "success", "id": 10}]
        api.pr = {"merged": True, "head": {"sha": HEAD}}
        second = controller.tick(self.state_dir, api, "michi[bot]", "key", self.requests, now=NOW + 1)
        self.assertEqual(second["phase"], "complete")
        self.assertEqual(second["head"], HEAD)
        self.assertEqual(len([x for x in api.calls if x[0] == "post" and "maintenance-decide.yml" in x[1]]), 1)

    def test_duplicate_dispatch_runs_are_not_selected_ambiguously(self):
        created = datetime.datetime.fromtimestamp(NOW, datetime.timezone.utc).isoformat()
        runs = [{"display_title": "Maintenance candidate request-1", "created_at": created} for _ in range(2)]
        api = FakeApi(runs=runs)
        with self.assertRaisesRegex(Blocked, "duplicate workflow dispatch"):
            controller.find_run(api, "maintenance-candidate.yml", "Maintenance candidate request-1", NOW)

    def test_stale_base_stops_before_review_or_dispatch(self):
        self.write_state(state_for("validating", self.policy_hash, pr=4, head=HEAD))
        api = FakeApi(base="c" * 40)
        reviewer = mock.Mock()
        result = controller.tick(self.state_dir, api, "michi[bot]", "key", self.requests,
                                 now=NOW, reviewer=reviewer)
        self.assertEqual(result["phase"], "needs_owner")
        reviewer.assert_not_called()
        self.assertFalse(any(x[0] == "post" for x in api.calls))

    def test_interrupted_inflight_review_is_not_retried(self):
        self.write_state(state_for("reviewing", self.policy_hash, pr=4, head=HEAD))
        api = FakeApi()
        reviewer = mock.Mock()
        result = controller.tick(self.state_dir, api, "michi[bot]", "key", self.requests,
                                 now=NOW, reviewer=reviewer)
        self.assertEqual(result["phase"], "needs_owner")
        self.assertIn("interrupted", result["summary"])
        reviewer.assert_not_called()

    def test_same_blocked_candidate_does_not_repeat_model_review(self):
        self.write_state(state_for("needs_owner", self.policy_hash, summary="candidate blocked"))
        api = FakeApi()
        reviewer = mock.Mock()
        with mock.patch("maintenance.controller.issue") as alert:
            result = controller.tick(self.state_dir, api, "michi[bot]", "key", self.requests,
                                     now=NOW + 1, reviewer=reviewer)
        self.assertEqual(result["phase"], "needs_owner")
        reviewer.assert_not_called()
        alert.assert_called_once()

    def test_watchdog_requires_fresh_successful_heartbeat(self):
        fresh = datetime.datetime.fromtimestamp(NOW - 3600, datetime.timezone.utc).isoformat().replace("+00:00", "Z")
        with mock.patch("maintenance.cli.github", return_value=mock.Mock(get=mock.Mock(return_value={
            "workflow_runs": [{"conclusion": "success", "created_at": fresh}]}))):
            cli.watchdog(mock.Mock())
        stale = datetime.datetime.fromtimestamp(NOW - 19 * 3600, datetime.timezone.utc).isoformat().replace("+00:00", "Z")
        with mock.patch("maintenance.cli.time.time", return_value=NOW), mock.patch(
                "maintenance.cli.github", return_value=mock.Mock(get=mock.Mock(return_value={
                    "workflow_runs": [{"conclusion": "success", "created_at": stale}]}))):
            with self.assertRaisesRegex(Blocked, "heartbeat"):
                cli.watchdog(mock.Mock())

    def test_startup_credential_failure_queues_owner_alert(self):
        args = mock.Mock(state=self.state_dir, app_id="1", installation_id="2", app_login="michi[bot]",
                         requests=self.requests)
        with mock.patch("maintenance.controller.controller_api", side_effect=Blocked("credential unavailable")), \
             mock.patch("maintenance.controller.issue") as alert:
            with self.assertRaisesRegex(Blocked, "startup failed"):
                cli.tick(args)
        alert.assert_called_once()


class ReviewTests(unittest.TestCase):
    def setUp(self):
        self.policy, _ = load_policy(ROOT)
        self.expected = {"schema": 1, "repository": "averagechris/dotfiles", "pr": 4,
                         "base": BASE, "head": HEAD, "policy_sha256": "d" * 64}
        self.evidence = {"run_id": 8, "shards": []}
        self.context = {"repository_files_from_trusted_base": {"docs/README.md": "docs"}}

    @staticmethod
    def response(decision="merge", status="completed"):
        holds = [{"id": name, "decision": "retain", "rationale": "Still needed", "sources": []}
                 for name in load_policy(ROOT)[0]["holds"]]
        text = json.dumps({"decision": decision, "summary": "Reviewed candidate.", "unresolved": [], "holds": holds})
        return {"status": status, "output": [{"type": "message", "content": [{"type": "output_text", "text": text}]}]}

    def test_exact_model_effort_tool_free_packet_and_immutable_identity(self):
        bodies = []
        decision = review("secret-api-key", self.policy, self.expected, self.evidence, self.context,
                          now=NOW, transport=lambda body: (bodies.append(body) or self.response()))
        body = bodies[0]
        self.assertEqual(body["model"], "gpt-6.1-sol")
        self.assertEqual(body["reasoning"], {"effort": "high"})
        self.assertNotIn("tools", body)
        self.assertNotIn("api_key", json.dumps(body))
        self.assertEqual(decision["base"], BASE)
        self.assertEqual(decision["head"], HEAD)
        self.assertEqual(decision["pr"], 4)
        self.assertEqual(decision["evidence_sha256"], digest(dumps(self.evidence).encode()))
        self.assertEqual(decision["decision"], "merge")
        gate.verify_identity(decision, self.expected)
        with self.assertRaisesRegex(Blocked, "different candidate"):
            gate.verify_identity(decision, {**self.expected, "head": "f" * 40})

    def test_review_api_error_incomplete_and_refusal_fail_closed(self):
        for transport in (
            lambda body: (_ for _ in ()).throw(Blocked("API error")),
            lambda body: {"status": "incomplete", "output": []},
            lambda body: {"status": "completed", "output": [{"type": "refusal", "refusal": "no"}]},
        ):
            with self.subTest(transport=transport), self.assertRaises(Blocked):
                review("key", self.policy, self.expected, self.evidence, self.context,
                       now=NOW, transport=transport)

    def test_hold_decision_is_not_merge_approval(self):
        result = review("key", self.policy, self.expected, self.evidence, self.context,
                        now=NOW, transport=lambda body: self.response(decision="hold"))
        self.assertEqual(result["decision"], "hold")
        self.assertNotEqual(result["decision"], "merge")


if __name__ == "__main__":
    unittest.main()
