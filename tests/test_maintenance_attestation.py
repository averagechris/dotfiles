"""Mocked CLI checks for trusted macOS certificate bundle evidence."""
from __future__ import annotations

import copy
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from maintenance import cli, gate
from maintenance.common import Blocked


class AttestationAcceptanceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.identity = gate.identity("d" * 64, 12, "a" * 40, "b" * 40)
        self.policy = {"max_evidence_age_seconds": 3600, "holds": {"emudhra": {
            "healthy_endpoint": "https://healthy.example", "reject_endpoints": [
                "https://reject-one.example", "https://reject-two.example"]}}}
        self.policy_file = self.root / "policy.json"
        self.policy_file.write_text("{}")
        self.identity_file = self.root / "identity.json"
        self.identity_file.write_text(json.dumps(self.identity))
        self.attestation_file = self.root / "attestation.json"
        self.output_file = self.root / "accepted.json"
        self.endpoints = {self.policy["holds"]["emudhra"]["healthy_endpoint"]: 0,
                          **{endpoint: 60 for endpoint in self.policy["holds"]["emudhra"]["reject_endpoints"]}}
        rows = []
        for bundle in ("system", "keychain"):
            for endpoint, code in self.endpoints.items():
                rows.append({"bundle": bundle, "bundle_sha256": "e" * 64,
                             "endpoint": endpoint, "exit_code": code})
        self.attestation = {**self.identity, "host": "suremac", "check": "macos-keychain",
                            "status": "passed", "created_at": 2_000_000_000, "checks": rows}
        self.write_attestation()
        self.args = SimpleNamespace(trusted=self.policy_file, identity=self.identity_file,
                                     attestation=self.attestation_file, output=self.output_file)

    def tearDown(self):
        self.temp.cleanup()

    def write_attestation(self):
        self.attestation_file.write_text(json.dumps(self.attestation))

    def accept(self):
        with mock.patch.object(cli, "load_policy", return_value=(self.policy, "d" * 64)), \
             mock.patch.dict(os.environ, {"MAINTENANCE_HOST_ATTESTOR_LOGIN": "attestor[bot]",
                                          "GITHUB_ACTOR": "attestor[bot]"}, clear=True), \
             mock.patch.object(cli.time, "time", return_value=2_000_000_100):
            cli.accept_attestation(self.args)

    def test_accepts_exact_six_distinct_slot_endpoint_probes_even_with_same_digest(self):
        # Prepare's platform-independent proof is separate from host identity.
        prepared = {**self.identity, "ancestry": {"emudhra": {"verified": True}}}
        self.identity_file.write_text(json.dumps(prepared))
        self.accept()
        accepted = json.loads(self.output_file.read_text())
        self.assertEqual(len(accepted["checks"]), 6)

    def test_missing_or_duplicate_slot_endpoint_probe_is_rejected(self):
        for rows in (self.attestation["checks"][:-1],
                     self.attestation["checks"][:-1] + [copy.deepcopy(self.attestation["checks"][0])]):
            self.attestation["checks"] = rows
            self.write_attestation()
            with self.subTest(rows=rows), self.assertRaises(Blocked):
                self.accept()

    def test_each_bundle_slot_requires_positive_and_both_negative_controls(self):
        rows = [row for row in self.attestation["checks"] if row["bundle"] == "system"]
        rows[-1]["endpoint"] = self.endpoints.__iter__().__next__()
        rows[-1]["exit_code"] = 0
        self.attestation["checks"] = rows + [row for row in self.attestation["checks"] if row["bundle"] == "keychain"]
        self.write_attestation()
        with self.assertRaises(Blocked):
            self.accept()

    def test_wrong_identity_policy_host_freshness_or_sender_is_rejected(self):
        for field, value in (("head", "c" * 40), ("host", "other"), ("created_at", 1_000_000_000)):
            self.attestation[field] = value
            self.write_attestation()
            with self.subTest(field=field), self.assertRaises(Blocked):
                self.accept()
            self.attestation = {**self.identity, "host": "suremac", "check": "macos-keychain",
                                "status": "passed", "created_at": 2_000_000_000,
                                "checks": self.attestation["checks"]}
        with mock.patch.object(cli, "load_policy", return_value=(self.policy, "f" * 64)), \
             mock.patch.dict(os.environ, {"MAINTENANCE_HOST_ATTESTOR_LOGIN": "attestor[bot]",
                                          "GITHUB_ACTOR": "attacker"}, clear=True):
            with self.assertRaises(Blocked):
                cli.accept_attestation(self.args)


if __name__ == "__main__":
    unittest.main()
