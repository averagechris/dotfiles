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
from maintenance.common import Blocked, Transient, digest, dumps, load_policy
from maintenance.review import review


ROOT = Path(__file__).resolve().parents[1]
BASE = "a" * 40
HEAD = "b" * 40
NOW = 1_800_000_000


class FakeApi:
    def __init__(self, *, base=BASE, runs=None, artifacts=None, post_error=None, fail_path=None, pr=None,
                 get_error=None):
        self.base, self.runs, self.artifacts, self.post_error = base, runs or [], artifacts or {}, post_error
        self.get_error = get_error
        self.fail_path = fail_path
        self.pr = pr or {"merged": False, "head": {"sha": HEAD}}
        self.calls = []

    def get(self, path):
        self.calls.append(("get", path))
        if self.get_error:
            raise self.get_error
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
             mock.patch("maintenance.controller.policy_at", return_value=({**self.policy, "merge_enabled": True}, self.policy_hash)), \
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

    def test_dry_run_records_successful_review_without_merge_dispatch(self):
        self.write_state(state_for("validating", self.policy_hash, pr=4, head=HEAD))
        created = datetime.datetime.fromtimestamp(NOW, datetime.timezone.utc).isoformat()
        api = FakeApi(runs=[{"display_title": "Maintenance validation " + HEAD, "created_at": created,
                             "status": "completed", "conclusion": "success", "id": 8}])
        decision = {"decision": "merge", "summary": "passed", "unresolved": [], "holds": {}}
        with mock.patch("maintenance.controller.gate.verify_validation", return_value={"run_id": 9}), \
             mock.patch("maintenance.controller.gate.verify_sources", return_value={"nixpkgs": self.policy["holds"]["emudhra"]["revision"]}), \
             mock.patch("maintenance.controller.collect_context", return_value={}), \
             mock.patch("maintenance.controller.gate.verify_review") as verify, \
             mock.patch("maintenance.controller.issue") as alert:
            result = controller.tick(self.state_dir, api, "michi[bot]", "key", self.requests,
                                     now=NOW, reviewer=mock.Mock(return_value=decision))
        self.assertEqual(result["phase"], "complete", result)
        self.assertIn("disabled", result["summary"])
        self.assertEqual(json.loads((self.state_dir / "review.json").read_text()), decision)
        verify.assert_called_once()
        alert.assert_not_called()
        self.assertFalse(any(x[0] == "post" and "maintenance-decide.yml" in x[1] for x in api.calls))

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
        self.assertEqual(result["phase"], "failed")
        reviewer.assert_not_called()
        self.assertFalse(any(x[0] == "post" for x in api.calls))

    def test_superseded_or_expired_generation_releases_latch_quietly(self):
        for api, now in ((FakeApi(base="c" * 40), NOW + 1), (FakeApi(), NOW + 8 * 3600)):
            with self.subTest(now=now), mock.patch("maintenance.controller.issue") as alert:
                self.write_state(state_for("generating", self.policy_hash))
                result = controller.tick(self.state_dir, api, "michi[bot]", "key", self.requests,
                                         now=now)
            self.assertEqual(result["phase"], "failed")
            alert.assert_not_called()
            self.assertFalse(any(call[0] == "post" and "maintenance-candidate.yml" in call[1]
                                 for call in api.calls))

    def test_completed_decision_reconciles_pr_without_decision_artifact(self):
        self.write_state(state_for("deciding", self.policy_hash, pr=4, head=HEAD,
                                   decision_started_at=NOW))
        created = datetime.datetime.fromtimestamp(NOW, datetime.timezone.utc).isoformat()
        api = FakeApi(runs=[{"display_title": "Maintenance decision request-1", "created_at": created,
                             "status": "completed", "conclusion": "success", "id": 10}],
                      pr={"merged": True, "head": {"sha": HEAD}})
        api.artifact = mock.Mock(side_effect=AssertionError("PR status is authoritative"))
        result = controller.tick(self.state_dir, api, "michi[bot]", "key", self.requests, now=NOW + 1)
        self.assertEqual(result["phase"], "complete")
        api.artifact.assert_not_called()

    def test_completed_decision_without_exact_merge_requires_owner(self):
        self.write_state(state_for("deciding", self.policy_hash, pr=4, head=HEAD,
                                   decision_started_at=NOW))
        created = datetime.datetime.fromtimestamp(NOW, datetime.timezone.utc).isoformat()
        api = FakeApi(runs=[{"display_title": "Maintenance decision request-1", "created_at": created,
                             "status": "completed", "conclusion": "success", "id": 10}],
                      pr={"merged": False, "head": {"sha": HEAD}})
        api.artifact = mock.Mock(side_effect=AssertionError("artifact may be missing"))
        result = controller.tick(self.state_dir, api, "michi[bot]", "key", self.requests, now=NOW + 1)
        self.assertEqual(result["phase"], "needs_owner")
        api.artifact.assert_not_called()

    def test_missing_decision_run_expires_at_review_freshness_deadline(self):
        self.write_state(state_for("deciding", self.policy_hash, pr=4, head=HEAD,
                                   decision_started_at=NOW, decision_expires_at=NOW + 600))
        api = FakeApi()
        result = controller.tick(self.state_dir, api, "michi[bot]", "key", self.requests,
                                 now=NOW + 600)
        self.assertEqual(result["phase"], "needs_owner")
        self.assertIn("reconciliation window", result["summary"])

    def test_duplicate_decision_run_cannot_hold_latch_past_saved_expiry(self):
        self.write_state(state_for("deciding", self.policy_hash, pr=4, head=HEAD,
                                   decision_started_at=NOW, decision_expires_at=NOW + 600))
        created = datetime.datetime.fromtimestamp(NOW, datetime.timezone.utc).isoformat()
        duplicate = {"display_title": "Maintenance decision request-1", "created_at": created}
        api = FakeApi(runs=[duplicate, duplicate])
        result = controller.tick(self.state_dir, api, "michi[bot]", "key", self.requests,
                                 now=NOW + 601)
        self.assertEqual(result["phase"], "needs_owner")
        self.assertIn("reconciliation window", result["summary"])

    def test_new_generation_clears_old_candidate_wait_state(self):
        from maintenance.common import atomic_json
        self.write_state({"schema": 1, "phase": "idle", "last_generation": 0,
                          "last_heartbeat": NOW, "head": HEAD, "pr": 4, "url": "old-url",
                          "summary": "old summary", "awaiting_host_since": NOW,
                          "decision_started_at": NOW, "decision_expires_at": NOW + 1})
        atomic_json(self.requests / "request.json", {"id": "owner-1", "operation": "run"})
        result = controller.tick(self.state_dir, FakeApi(), "michi[bot]", "key", self.requests,
                                 now=NOW)
        self.assertEqual(result["phase"], "generating")
        for key in ("head", "pr", "url", "summary", "awaiting_host_since",
                    "decision_started_at", "decision_expires_at"):
            self.assertNotIn(key, result)

    def test_transient_failure_preserves_queued_run_and_alerts_after_one_hour(self):
        from maintenance.common import atomic_json
        atomic_json(self.requests / "request.json", {"id": "owner-1", "operation": "run"})
        with mock.patch("maintenance.controller.issue") as alert:
            first = controller.tick(self.state_dir, FakeApi(get_error=Transient("unavailable")),
                                    "michi[bot]", "key", self.requests, now=NOW)
            self.assertEqual(first["phase"], "idle")
            self.assertEqual(first["pending_run"]["id"], "owner-1")
            self.assertEqual(first["last_request"], "owner-1")
            alert.assert_not_called()

            second = controller.tick(self.state_dir, FakeApi(get_error=Transient("unavailable")),
                                     "michi[bot]", "key", self.requests, now=NOW + 3600)
            self.assertEqual(second["phase"], "idle")
            alert.assert_called_once()

        api = FakeApi()
        resumed = controller.tick(self.state_dir, api, "michi[bot]", "key",
                                  self.requests, now=NOW + 3601)
        self.assertEqual(resumed["phase"], "generating")
        self.assertEqual(resumed["last_request"], "owner-1")
        self.assertNotIn("pending_run", resumed)
        candidate_posts = [call for call in api.calls if call[0] == "post" and
                           "maintenance-candidate.yml" in call[1]]
        self.assertEqual(len(candidate_posts), 1)

    def test_queued_run_survives_pause_and_resume_requests(self):
        from maintenance.common import atomic_json
        self.write_state({"schema": 1, "phase": "idle", "paused": True})
        request_path = self.requests / "request.json"
        atomic_json(request_path, {"id": "owner-run", "operation": "run"})
        paused = controller.tick(self.state_dir, FakeApi(), "michi[bot]", "key", self.requests,
                                 now=NOW)
        self.assertTrue(paused["paused"])
        self.assertEqual(paused["pending_run"]["id"], "owner-run")

        atomic_json(request_path, {"id": "owner-resume", "operation": "resume"})
        api = FakeApi()
        resumed = controller.tick(self.state_dir, api, "michi[bot]", "key", self.requests,
                                  now=NOW + 1)
        self.assertFalse(resumed["paused"])
        self.assertEqual(resumed["phase"], "generating")
        self.assertEqual(resumed["last_request"], "owner-resume")
        self.assertEqual(sum(call[0] == "post" and "maintenance-candidate.yml" in call[1]
                             for call in api.calls), 1)

    def test_transient_candidate_dispatch_keeps_reconciliation_latch_without_early_alert(self):
        from maintenance.common import atomic_json
        self.write_state({"schema": 1, "phase": "idle", "last_generation": 0,
                          "last_heartbeat": NOW})
        atomic_json(self.requests / "request.json", {"id": "owner-1", "operation": "run"})
        api = FakeApi(post_error=Transient("server error"), fail_path="maintenance-candidate.yml")
        with mock.patch("maintenance.controller.issue") as alert:
            result = controller.tick(self.state_dir, api, "michi[bot]", "key", self.requests,
                                     now=NOW)
        self.assertEqual(result["phase"], "generating")
        self.assertEqual(result["last_request"], "owner-1")
        alert.assert_not_called()
        dispatches = [call for call in api.calls if call[0] == "post" and
                      "maintenance-candidate.yml" in call[1]]
        self.assertEqual(len(dispatches), 1)

        api.post_error = None
        waiting = controller.tick(self.state_dir, api, "michi[bot]", "key", self.requests,
                                  now=NOW + 1)
        self.assertEqual(waiting["phase"], "generating")
        self.assertEqual(len([call for call in api.calls if call[0] == "post" and
                              "maintenance-candidate.yml" in call[1]]), 1)

    def test_upstream_context_uses_bounded_nonempty_commit_sample(self):
        class CompareApi:
            def __init__(self):
                self.calls = []

            def file(self, path, ref):
                if path == "docs/README.md":
                    return b"trusted context"
                locked_rev = "old" if ref == BASE else "new"
                return json.dumps({"nodes": {"flake": {"locked": {
                    "type": "github", "owner": "upstream", "repo": "repo", "rev": locked_rev}}}}).encode()

            def get(self, path):
                self.calls.append(path)
                if "/compare/" in path:
                    return {"status": "ahead", "total_commits": 1, "html_url": "https://example.invalid/compare"}
                if path.endswith("/git/commits/new"):
                    return {"sha": "new", "message": "latest upstream change"}
                raise AssertionError(path)

        api = CompareApi()
        policy = {"context_files": ["docs/README.md"], "canonical_locks": ["flake.lock"]}
        result = controller.collect_context(api, policy, {"base": BASE, "head": HEAD},
                                            {"changed": ["flake.lock"]})
        self.assertEqual(result["upstream_changes"][0]["commits"],
                         [{"sha": "new", "message": "latest upstream change"}])
        self.assertIn("per_page=40&page=2", api.calls[0])
        self.assertIn("/git/commits/new", api.calls[1])

    def test_awaiting_host_alert_waits_one_hour_and_later_evidence_resumes_review(self):
        state = state_for("awaiting_host", self.policy_hash, pr=4, head=HEAD,
                           awaiting_host_since=NOW - 3599)
        self.write_state(state)
        validation_created = datetime.datetime.fromtimestamp(NOW, datetime.timezone.utc).isoformat()
        validation_run = {"display_title": "Maintenance validation " + HEAD,
                          "created_at": validation_created, "status": "completed",
                          "conclusion": "success", "head_sha": BASE, "id": 8}
        api = FakeApi(runs=[validation_run])
        changed_source = {"nixpkgs": "c" * 40, "changed": []}
        with mock.patch("maintenance.controller.gate.verify_validation", return_value={}), \
             mock.patch("maintenance.controller.gate.verify_sources", return_value=changed_source), \
             mock.patch("maintenance.controller.issue") as alert:
            waiting = controller.tick(self.state_dir, api, "michi[bot]", "key", self.requests,
                                      now=NOW)
            self.assertEqual(waiting["phase"], "awaiting_host")
            alert.assert_not_called()

            overdue = controller.tick(self.state_dir, api, "michi[bot]", "key", self.requests,
                                      now=NOW + 2)
            self.assertEqual(overdue["phase"], "awaiting_host")
            alert.assert_called_once()

        self.write_state({**overdue, "awaiting_host_since": NOW - 4000})
        api.runs = [validation_run, {"display_title": "Maintenance host attestation " + HEAD,
                     "head_sha": BASE, "conclusion": "success", "id": 99}]
        evidence = {"run_id": 8, "shards": []}
        decision = {"decision": "merge", "summary": "passed", "unresolved": [], "holds": {}}
        with mock.patch("maintenance.controller.gate.verify_validation", return_value=evidence), \
             mock.patch("maintenance.controller.gate.verify_sources", return_value=changed_source), \
             mock.patch("maintenance.controller.gate.attach_host_attestation", return_value=evidence), \
             mock.patch("maintenance.controller.collect_context", return_value={}), \
             mock.patch("maintenance.controller.gate.verify_review"), \
             mock.patch("maintenance.controller.issue") as alert:
            resumed = controller.tick(self.state_dir, api, "michi[bot]", "key", self.requests,
                                      now=NOW + 3, reviewer=mock.Mock(return_value=decision))
        self.assertEqual(resumed["phase"], "complete")
        self.assertNotIn("awaiting_host_since", resumed)
        alert.assert_not_called()

    def test_transient_review_failure_stops_for_owner_without_retrying_model(self):
        self.write_state(state_for("validating", self.policy_hash, pr=4, head=HEAD))
        created = datetime.datetime.fromtimestamp(NOW, datetime.timezone.utc).isoformat()
        api = FakeApi(runs=[{"display_title": "Maintenance validation " + HEAD, "created_at": created,
                             "status": "completed", "conclusion": "success", "id": 8}])
        reviewer = mock.Mock(side_effect=Transient("review unavailable"))
        with mock.patch("maintenance.controller.gate.verify_validation", return_value={}), \
             mock.patch("maintenance.controller.gate.verify_sources", return_value={"nixpkgs": self.policy["holds"]["emudhra"]["revision"], "changed": []}), \
             mock.patch("maintenance.controller.collect_context", return_value={}), \
             mock.patch("maintenance.controller.issue") as alert:
            result = controller.tick(self.state_dir, api, "michi[bot]", "key", self.requests,
                                     now=NOW, reviewer=reviewer)
        self.assertEqual(result["phase"], "needs_owner")
        reviewer.assert_called_once()
        alert.assert_called_once()

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
