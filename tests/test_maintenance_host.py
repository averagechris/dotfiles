#!/usr/bin/env python3
"""Mock-only tests for Suremac maintenance host attestation."""
from __future__ import annotations

import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from maintenance import cli, gate, host
from maintenance.common import Blocked, dumps, load_policy


ROOT = Path(__file__).resolve().parents[1]
BASE = "a" * 40
HEAD = "b" * 40
APP = "dotfiles-maintenance[bot]"
ATTESTOR = "suremac-attestor"
NOW = 1_800_000_000


class HostApi:
    def __init__(self, *, login=ATTESTOR, nixpkgs="c" * 40, attestation_runs=None):
        self.login, self.nixpkgs = login, nixpkgs
        self.attestation_runs = attestation_runs or []
        self.calls = []
        self.posts = []
        self.pr = {
            "number": 42, "state": "open", "draft": False,
            "user": {"login": APP},
            "head": {"repo": {"full_name": "averagechris/dotfiles"}, "ref": "maintenance/candidate", "sha": HEAD},
            "base": {"repo": {"full_name": "averagechris/dotfiles"}, "ref": "main", "sha": BASE},
        }
        self.policy, self.policy_hash = load_policy(ROOT)

    def get(self, path):
        self.calls.append(("get", path))
        if path == "/user":
            return {"login": self.login}
        if path.endswith("/git/ref/heads/main"):
            return {"object": {"sha": BASE}}
        if path.endswith("/pulls/42"):
            return self.pr
        raise AssertionError(f"unexpected GET {path}")

    def pages(self, path, key=None):
        self.calls.append(("pages", path))
        if "/pulls?" in path:
            return [self.pr]
        if "/pulls/42/commits" in path:
            return [{"sha": HEAD, "parents": [{"sha": BASE}]}]
        if "maintenance-validate.yml/runs" in path:
            return [{"display_title": "Maintenance validation " + HEAD,
                     "path": self.policy["validation_workflow"], "event": "workflow_dispatch",
                     "head_branch": "main", "head_sha": BASE, "status": "completed",
                     "conclusion": "success", "id": 55}]
        if "maintenance-attest.yml/runs" in path:
            return self.attestation_runs
        raise AssertionError(f"unexpected pages {path}")

    def file(self, path, ref):
        self.calls.append(("file", path, ref))
        return (ROOT / path).read_bytes()

    def artifact(self, run_id, name):
        self.calls.append(("artifact", run_id, name))
        return {"run_id": run_id}

    def post(self, path, value):
        self.posts.append((path, value))
        return {}


class HostAttestorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.state = Path(self.temp.name) / "state"

    def tearDown(self):
        self.temp.cleanup()

    @staticmethod
    def local_result(api, policy, expected, now):
        return {**expected, "host": "suremac", "check": "macos-keychain", "status": "passed",
                "created_at": now, "checks": []}

    def tick(self, api, **kwargs):
        with mock.patch("maintenance.host.socket.gethostname", return_value="suremac.local"), \
             mock.patch("maintenance.host.gate.verify_sources", return_value={"nixpkgs": api.nixpkgs}), \
             mock.patch("maintenance.host.gate.verify_validation", return_value={"run_id": 55}), \
             mock.patch("maintenance.host._run_local_attestor", side_effect=self.local_result) as local:
            result = host.tick(self.state, api, APP, ATTESTOR, NOW)
        return result, local

    def test_dispatch_contains_exact_identity_and_attestation_and_dedupes(self):
        api = HostApi()
        result, local = self.tick(api)
        self.assertEqual(result["phase"], "submitted")
        local.assert_called_once()
        self.assertEqual(len(api.posts), 1)
        path, payload = api.posts[0]
        self.assertTrue(path.endswith("/maintenance-attest.yml/dispatches"))
        supplied = payload["inputs"]
        self.assertEqual(supplied["base"], BASE)
        self.assertEqual(supplied["head"], HEAD)
        self.assertEqual(supplied["pr"], "42")
        attestation = json.loads(supplied["attestation"])
        self.assertEqual(attestation["repository"], "averagechris/dotfiles")
        self.assertEqual(attestation["base"], BASE)
        self.assertEqual(attestation["head"], HEAD)
        self.assertEqual(attestation["created_at"], NOW)

        result, local_again = self.tick(api)
        self.assertEqual(result["phase"], "submitted")
        local_again.assert_not_called()
        self.assertEqual(len(api.posts), 1)

    def test_attestation_not_needed_when_hold_revision_unchanged(self):
        api_rev = load_policy(ROOT)[0]["holds"]["emudhra"]["revision"]
        api = HostApi(nixpkgs=api_rev)
        with mock.patch("maintenance.host.socket.gethostname", return_value="suremac"), \
             mock.patch("maintenance.host.gate.verify_sources", return_value={"nixpkgs": api_rev}), \
             mock.patch("maintenance.host._run_local_attestor") as local:
            result = host.tick(self.state, api, APP, ATTESTOR, NOW)
        self.assertEqual(result["phase"], "not_required")
        local.assert_not_called()
        self.assertEqual(api.posts, [])

    def test_lost_dispatch_checks_exact_run_before_considering_retry(self):
        api = HostApi()
        self.tick(api)
        api.attestation_runs = [{"display_title": "Maintenance host attestation " + HEAD,
                                 "path": host.ATTEST_WORKFLOW, "event": "workflow_dispatch",
                                 "head_branch": "main", "head_sha": BASE,
                                 "actor": {"login": ATTESTOR}, "status": "in_progress", "id": 90}]
        result, local = self.tick(api)
        self.assertEqual(result["phase"], "in_progress")
        local.assert_not_called()
        self.assertEqual(len(api.posts), 1)

    def test_wrong_machine_or_api_identity_is_blocked(self):
        api = HostApi()
        with mock.patch("maintenance.host.socket.gethostname", return_value="thorny"):
            with self.assertRaisesRegex(Blocked, "only on suremac"):
                host.tick(self.state, api, APP, ATTESTOR, NOW)
        with mock.patch("maintenance.host.socket.gethostname", return_value="suremac" ):
            with self.assertRaisesRegex(Blocked, "different identity"):
                host.tick(self.state, HostApi(login="someone-else"), APP, ATTESTOR, NOW)

    def test_token_file_requires_explicit_absolute_mode_0600(self):
        token = Path(self.temp.name) / "github-token"
        token.write_text("ghp_synthetic\n")
        token.chmod(0o600)
        self.assertEqual(host.token_from_file(token), "ghp_synthetic")
        token.chmod(0o640)
        with self.assertRaisesRegex(Blocked, "mode-0600"):
            host.token_from_file(token)
        with self.assertRaisesRegex(Blocked, "absolute"):
            host.token_from_file(Path("relative-token"))

    def test_cli_uses_only_explicit_token_file(self):
        token = Path(self.temp.name) / "token"
        token.write_text("ghp_synthetic")
        token.chmod(0o600)
        with mock.patch.dict(os.environ, {"GH_TOKEN": "ambient-broad-token"}, clear=True), \
             mock.patch("maintenance.host.GitHub") as github, \
             mock.patch("maintenance.host.tick", return_value={"phase": "idle"}) as run:
            self.assertIsNone(host.main(["tick", "--state", str(self.state), "--app-login", APP,
                                         "--attestor-login", ATTESTOR, "--token-file", str(token)]))
        github.assert_called_once_with("ghp_synthetic")
        self.assertEqual(run.call_args.args[1], github.return_value)

    def test_local_probe_reuses_trusted_attestor_with_isolated_policy(self):
        api = HostApi()
        expected = gate.identity(api.policy_hash, 42, BASE, HEAD)
        captured = {}

        def attest(args):
            captured["policy"] = json.loads((args.trusted / "maintenance/policy.json").read_bytes())
            captured["identity"] = json.loads(args.identity.read_bytes())
            args.output.write_text(json.dumps({**expected, "host": "suremac", "check": "macos-keychain",
                                               "status": "passed", "created_at": NOW, "checks": []}))

        with mock.patch("maintenance.host.cli.attest", side_effect=attest) as probe:
            value = host._run_local_attestor(api, api.policy, expected, NOW)
        probe.assert_called_once()
        self.assertEqual(captured["identity"], expected)
        self.assertEqual(captured["policy"], api.policy)
        self.assertEqual(value["head"], HEAD)

    def test_nix_module_is_disabled_by_default_and_requires_token_path(self):
        module = (ROOT / "flakes/hosts/suremac/maintenance-attestor.nix").read_text()
        self.assertIn('lib.mkEnableOption "Suremac certificate hold attestation', module)
        self.assertIn("config = lib.mkIf cfg.enable", module)
        self.assertIn("cfg.tokenFile != null && lib.hasPrefix \"/\" cfg.tokenFile", module)
        self.assertIn("StartInterval = 900", module)
        self.assertIn("RunAtLoad = true", module)


if __name__ == "__main__":
    unittest.main()
