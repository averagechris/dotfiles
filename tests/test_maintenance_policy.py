#!/usr/bin/env python3
"""Behavioral tests for the trusted maintenance policy and bounded I/O helpers."""

from __future__ import annotations

import io
import copy
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock
import zipfile
import sys
import urllib.error

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from maintenance.common import Blocked, GitHub, MAX_JSON, Transient, credential, json_bytes, load_policy
from maintenance.policy import check_contents, check_lock, local_check, package_shape, safe_path


REV_A = "a" * 40
REV_B = "b" * 40


def lock(rev: str = REV_A, *, shared_rev: str = REV_A, inputs=None) -> dict:
    return {
        "version": 7,
        "root": "root",
        "nodes": {
            "root": {"inputs": inputs or {"nixpkgs": "nixpkgs", "t3-code-nix": "t3-code-nix"}},
            "nixpkgs": {
                "original": {"type": "github", "owner": "NixOS", "repo": "nixpkgs", "ref": "nixos-unstable"},
                "locked": {"type": "github", "owner": "NixOS", "repo": "nixpkgs", "rev": rev},
            },
            "t3-code-nix": {
                "original": {"type": "github", "owner": "example", "repo": "t3-code-nix"},
                "locked": {"type": "github", "owner": "example", "repo": "t3-code-nix", "rev": "c" * 40},
                "inputs": {"nixpkgs": ["nixpkgs"]},
            },
            "deploy-rs": {
                "original": {"type": "github", "owner": "serokell", "repo": "deploy-rs"},
                "locked": {"type": "github", "owner": "serokell", "repo": "deploy-rs", "rev": shared_rev},
            },
        },
    }


def policy(*locks: str) -> dict:
    return {"max_changed_files": 20, "canonical_locks": list(locks), "manual_packages": ["pkg.nix"]}


class PolicyLockTests(unittest.TestCase):
    def test_repository_lock_graphs_are_eligible_without_source_changes(self):
        root = Path(__file__).resolve().parents[1]
        config, _ = load_policy(root)
        content = lambda name: (root / name).read_bytes()
        check_contents(config, config["canonical_locks"], content, content)

    def test_existing_redirected_tarball_can_remain_but_cannot_change(self):
        before = lock()
        before["nodes"]["legacy"] = {
            "original": {"type": "tarball", "url": "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz"},
            "locked": {"type": "tarball", "url": "https://releases.nixos.org/release/nixexprs.tar.xz", "narHash": "existing"},
        }
        check_lock(before, copy.deepcopy(before))
        for change in ({"url": "https://attacker.invalid/source.tar.gz"}, {"narHash": "new"}):
            after = copy.deepcopy(before)
            after["nodes"]["legacy"]["locked"].update(change)
            with self.subTest(change=change), self.assertRaisesRegex(Blocked, "redirected tarball changed"):
                check_lock(before, after)

    def test_protected_path_and_unsafe_path_rejected_with_callbacks(self):
        old, new = lock(), lock()
        files = {"flake.lock": json.dumps(new).encode()}
        callback = lambda path: files[path]
        with self.assertRaisesRegex(Blocked, "protected paths"):
            check_contents(policy("flake.lock"), ["docs/deploy.md"], callback, callback)
        with self.assertRaisesRegex(Blocked, "invalid changed path"):
            safe_path("../flake.lock")

    def test_changed_original_source_url_requires_owner_review(self):
        before, after = lock(), lock()
        after["nodes"]["deploy-rs"]["original"]["owner"] = "attacker"
        with self.assertRaisesRegex(Blocked, "source"):
            check_lock(before, after)

    def test_locked_source_identity_cannot_diverge_from_original(self):
        before, after = lock(), lock()
        after["nodes"]["deploy-rs"]["locked"]["repo"] = "attacker-repo"
        with self.assertRaises(Blocked):
            check_lock(before, after)

    def test_explicit_revision_pin_cannot_move(self):
        before, after = lock(), lock()
        node = before["nodes"]["deploy-rs"]
        node["original"]["rev"] = REV_A
        node["locked"]["rev"] = REV_A
        changed = after["nodes"]["deploy-rs"]
        changed["original"]["rev"] = REV_A
        changed["locked"]["rev"] = REV_B
        with self.assertRaisesRegex(Blocked, "explicit revision pin changed"):
            check_lock(before, after)

    def test_version_tag_lock_cannot_move(self):
        before, after = lock(), lock()
        for value in (before, after):
            node = value["nodes"]["deploy-rs"]
            node["original"]["ref"] = "v1.2.3"
            node["locked"]["rev"] = REV_A
        after["nodes"]["deploy-rs"]["locked"]["rev"] = REV_B
        with self.assertRaisesRegex(Blocked, "version tag moved"):
            check_lock(before, after)

    def test_root_input_topology_cannot_change(self):
        before, after = lock(), lock(inputs={"nixpkgs": "nixpkgs", "extra": "deploy-rs"})
        with self.assertRaisesRegex(Blocked, "root input topology"):
            check_lock(before, after)

    def test_shared_revisions_must_match_across_canonical_locks(self):
        paths = ["flake.lock", "flakes/hosts/test/flake.lock"]
        root, child = lock(), lock()
        moved_child = lock(shared_rev=REV_B)
        initial = {paths[0]: json.dumps(root).encode(), paths[1]: json.dumps(child).encode()}
        updated = {paths[0]: initial[paths[0]], paths[1]: json.dumps(moved_child).encode()}
        with self.assertRaisesRegex(Blocked, "shared deploy-rs revisions differ"):
            check_contents(policy(*paths), [paths[1]], initial.__getitem__, updated.__getitem__)

    def test_host_specific_explicit_pin_remains_distinct_from_shared_input(self):
        paths = ["flake.lock", "flakes/hosts/test/flake.lock"]
        root, child = lock(shared_rev=REV_B), lock()
        child["nodes"]["deploy-rs"]["original"]["rev"] = REV_A
        files = {paths[0]: json.dumps(root).encode(), paths[1]: json.dumps(child).encode()}
        check_contents(policy(*paths), [paths[0]], files.__getitem__, files.__getitem__)


class PackageAndJsonTests(unittest.TestCase):
    def test_package_version_and_hash_values_can_change_but_code_cannot(self):
        old = 'version = "1.2.3";\nhash = "sha256-' + "A" * 43 + '=";\n'
        new = 'version = "2.3.4";\nhash = "sha256-' + "B" * 43 + '=";\n'
        self.assertEqual(package_shape(old), package_shape(new))
        with self.assertRaisesRegex(Blocked, "package code"):
            check_contents(
                policy("flake.lock"), ["pkg.nix"],
                lambda name: old.encode() if name == "pkg.nix" else json.dumps(lock()).encode(),
                lambda name: (new + "builtins.abort \"oops\";\n").encode() if name == "pkg.nix" else json.dumps(lock()).encode(),
            )

    def test_corrupt_and_oversized_json_rejected(self):
        with self.assertRaises(json.JSONDecodeError):
            json_bytes(b"{broken")
        with self.assertRaisesRegex(Blocked, "size limit"):
            json_bytes(b" " * (MAX_JSON + 1))


class CommonIOTests(unittest.TestCase):
    def test_temporary_transport_failures_are_distinct_from_missing_access(self):
        for error, expected in ((OSError("offline"), Transient),
                                (urllib.error.HTTPError("ignored", 502, "server", {}, None), Transient),
                                (urllib.error.HTTPError("ignored", 429, "rate limit", {}, None), Transient),
                                (urllib.error.HTTPError("ignored", 403, "access", {}, None), Blocked)):
            with self.subTest(error=error), mock.patch("maintenance.common.urllib.request.build_opener") as opener:
                opener.return_value.open.side_effect = error
                with self.assertRaises(expected) as raised:
                    GitHub("private-token").get("/example")
                if expected is Blocked:
                    self.assertNotIsInstance(raised.exception, Transient)
                self.assertNotIn("private-token", str(raised.exception))

    def test_credential_does_not_use_ambient_broad_token_fallback(self):
        with mock.patch.dict(os.environ, {"GH_TOKEN": "broad-token", "GITHUB_TOKEN": "also-broad"}, clear=True):
            with self.assertRaisesRegex(Blocked, "missing token credential"):
                credential("token")

    def test_local_check_rejects_symlink_changed_file(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            trusted, candidate, outside = root / "trusted", root / "candidate", root / "outside"
            trusted.mkdir()
            candidate.mkdir()
            outside.write_bytes(json.dumps(lock()).encode())
            (trusted / "flake.lock").write_bytes(json.dumps(lock()).encode())
            (candidate / "flake.lock").symlink_to(outside)
            git_results = [
                subprocess.CompletedProcess([], 0, stdout="M\tflake.lock\n", stderr=""),
                subprocess.CompletedProcess([], 0, stdout="", stderr=""),
            ]
            with mock.patch("maintenance.policy.subprocess.run", side_effect=git_results):
                with self.assertRaisesRegex(Blocked, "symlink"):
                    local_check(policy("flake.lock"), trusted, candidate)

    def test_artifact_archive_paths_are_rejected_without_extraction(self):
        archive_bytes = io.BytesIO()
        with zipfile.ZipFile(archive_bytes, "w") as archive:
            archive.writestr("../evidence.json", "{}")
        client = GitHub("test-token")
        with mock.patch.object(client, "pages", return_value=[{"id": 1, "name": "evidence", "expired": False}]), \
             mock.patch.object(client, "request", return_value=archive_bytes.getvalue()):
            with self.assertRaisesRegex(Blocked, "unexpected evidence archive"):
                client.artifact(123, "evidence")


if __name__ == "__main__":
    unittest.main()
