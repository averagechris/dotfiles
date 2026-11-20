#!/usr/bin/env python3
"""Offline orchestration tests for maintenance candidate generation."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from maintenance.candidate import Candidate, MANUAL_PACKAGES, main
from maintenance.common import Blocked


REV_A, REV_B = "a" * 40, "b" * 40
CHILD = "flakes/base-lib/flake.lock"


def lock(rev=REV_A, *, root=True):
    nodes = {
        "root": {"inputs": {"nixpkgs": "nixpkgs", "t3-code-nix": "t3-code-nix"}},
        "nixpkgs": {
            "original": {"type": "github", "owner": "NixOS", "repo": "nixpkgs", "ref": "nixos-unstable"},
            "locked": {"type": "github", "owner": "NixOS", "repo": "nixpkgs", "rev": rev},
        },
        "deploy-rs": {
            "original": {"type": "github", "owner": "serokell", "repo": "deploy-rs"},
            "locked": {"type": "github", "owner": "serokell", "repo": "deploy-rs", "rev": rev},
        },
        "t3-code-nix": {
            "original": {"type": "github", "owner": "example", "repo": "t3-code-nix"},
            "locked": {"type": "github", "owner": "example", "repo": "t3-code-nix", "rev": "c" * 40},
            "inputs": {"nixpkgs": ["nixpkgs"]},
        },
    }
    if root:
        nodes["root"]["inputs"]["base-lib"] = "base-lib"
        nodes["base-lib"] = {
            "original": {"type": "path", "path": "./flakes/base-lib"},
            "locked": {"type": "path", "path": "./flakes/base-lib"},
        }
    return {"version": 7, "root": "root", "nodes": nodes}


class CandidateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.trusted = self.root / "trusted"
        self.candidate = self.root / "candidate"
        self.output = self.root / "artifact.json"
        self.trusted.mkdir()
        (self.trusted / "maintenance").mkdir()
        (self.trusted / "flakes/base-lib").mkdir(parents=True)
        policy_path = Path(__file__).resolve().parents[1] / "maintenance/policy.json"
        policy = json.loads(policy_path.read_text())
        policy["canonical_locks"] = ["flake.lock", CHILD]
        policy["manual_packages"] = ["flakes/base-lib/packages/pi-coding-agent.nix", "flakes/base-lib/packages/helium-bin.nix"]
        (self.trusted / "maintenance/policy.json").write_text(json.dumps(policy))
        (self.trusted / "flake.lock").write_text(json.dumps(lock(), indent=2, sort_keys=True) + "\n")
        (self.trusted / CHILD).write_text(json.dumps(lock(root=False), indent=2, sort_keys=True) + "\n")
        (self.trusted / "flake.nix").write_text("{}\n")
        (self.trusted / "README.md").write_text("base\n")
        self.git(self.trusted, "init", "-q")
        self.git(self.trusted, "config", "user.email", "test@example.invalid")
        self.git(self.trusted, "config", "user.name", "Test")
        self.git(self.trusted, "add", ".")
        self.git(self.trusted, "-c", "commit.gpgsign=false", "commit", "-qm", "base")
        subprocess.run(["git", "clone", "-q", str(self.trusted), str(self.candidate)], check=True)

    def tearDown(self):
        self.temp.cleanup()

    @staticmethod
    def git(root, *args):
        return subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True, text=True).stdout.strip()

    def runner(self, *, update=True, fail=False):
        calls = []

        def run(argv, **kwargs):
            if argv[0] != "nix":
                return subprocess.run(argv, **kwargs)
            calls.append((argv, kwargs))
            if fail and argv[1] == "run":
                return subprocess.CompletedProcess(argv, 7, stdout="failed updater")
            if argv[1] == "run" and update:
                path = self.candidate / "flake.lock"
                data = json.loads(path.read_text())
                data["nodes"]["deploy-rs"]["locked"]["rev"] = REV_B
                path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
            if argv[1:3] == ["flake", "update"]:
                output = Path(argv[argv.index("--output-lock-file") + 1])
                flake_ref = argv[argv.index("--flake") + 1]
                rel = "flake.lock" if "?dir=." in flake_ref else CHILD
                output.write_bytes((self.candidate / rel).read_bytes())
            return subprocess.CompletedProcess(argv, 0, stdout="ok")

        return run, calls

    def test_update_uses_trusted_app_and_syncs_shared_nodes_and_path_parent(self):
        runner, calls = self.runner()
        result = Candidate(self.trusted, self.candidate, self.output, run=runner).generate()
        self.assertFalse(result["noop"])
        updater, kwargs = calls[0]
        self.assertEqual(updater[:5], ["nix", "run", "--option", "sandbox", "true"])
        self.assertTrue(any(arg.endswith("#update-flakes") for arg in updater))
        self.assertIn("--show-output", updater)
        self.assertIn("--no-accept-flake-config", updater)
        self.assertEqual([updater[i + 1] for i, arg in enumerate(updater[:-1]) if arg == "--manual-package"], list(MANUAL_PACKAGES))
        self.assertNotIn("--ignore-cooldown", updater)
        self.assertEqual(Path(kwargs["env"]["DOTFILES_REPO_ROOT"]), self.candidate.resolve())
        self.assertNotIn("NIX_CONFIG", kwargs["env"])
        sync = [call[0] for call in calls[1:]]
        self.assertTrue(any("--offline" in argv and "base-lib" in argv for argv in sync))
        child = json.loads((self.candidate / CHILD).read_text())
        self.assertEqual(child["nodes"]["deploy-rs"]["locked"]["rev"], REV_B)
        self.assertEqual(child["nodes"]["deploy-rs"]["original"]["owner"], "serokell")
        self.assertIn("--no-accept-flake-config", sync[0])

    def test_noop_has_empty_artifact_files(self):
        runner, _ = self.runner(update=False)
        result = Candidate(self.trusted, self.candidate, self.output, run=runner).generate()
        self.assertEqual(result["noop"], True)
        self.assertEqual(result["files"], [])

    def test_path_inputs_refresh_dependency_first_and_batch_per_lock(self):
        paths = {
            "base": "flakes/base-lib/flake.lock",
            "module": "flakes/nixos-modules/module/flake.lock",
            "host": "flakes/hosts/host/flake.lock",
        }
        dirs = {name: self.candidate / Path(rel).parent for name, rel in paths.items()}
        for directory in dirs.values():
            directory.mkdir(parents=True, exist_ok=True)

        def write_lock(name, inputs):
            nodes = {"root": {"inputs": {}}}
            for input_name, (target, is_follows) in inputs.items():
                nodes["root"]["inputs"][input_name] = ["base-lib"] if is_follows else input_name
                if not is_follows:
                    relative = os.path.relpath(dirs[target], dirs[name])
                    nodes[input_name] = {"original": {"type": "path", "path": relative}}
            lock_path = self.candidate / paths[name]
            lock_path.write_text(json.dumps({"version": 7, "root": "root", "nodes": nodes}))

        write_lock("base", {})
        write_lock("module", {"base-lib": ("base", False)})
        # Host's two direct local inputs share a single update invocation. The
        # follows alias is not mistaken for another direct local path input.
        write_lock("host", {"module": ("module", False), "base-lib": ("base", False),
                             "alias": ("base", True)})
        calls = []

        def run(argv, **kwargs):
            calls.append(argv)
            output = Path(argv[argv.index("--output-lock-file") + 1])
            flake_ref = argv[argv.index("--flake") + 1]
            rel = next(rel for rel in paths.values()
                       if f"?dir={Path(rel).parent.as_posix()}" in flake_ref)
            output.write_bytes((self.candidate / rel).read_bytes())
            return subprocess.CompletedProcess(argv, 0, stdout="ok")

        policy = {"canonical_locks": list(paths.values())}
        Candidate(self.trusted, self.candidate, self.output, run=run)._path_parents(policy)
        order = [next(name for name, rel in paths.items()
                      if f"?dir={Path(rel).parent.as_posix()}" in argv[argv.index("--flake") + 1])
                 for argv in calls]
        self.assertEqual(order, ["module", "host"])
        self.assertEqual([argv[3:argv.index("--offline")] for argv in calls],
                         [["base-lib"], ["base-lib", "module"]])
        self.assertEqual(len(calls), 2)

    def test_path_input_cycle_fails_closed_before_running_nix(self):
        paths = {"one": "flakes/a/flake.lock", "two": "flakes/b/flake.lock"}
        dirs = {name: self.candidate / Path(rel).parent for name, rel in paths.items()}
        for directory in dirs.values():
            directory.mkdir(parents=True, exist_ok=True)
        for name, target in (("one", "two"), ("two", "one")):
            lock_path = self.candidate / paths[name]
            relative = os.path.relpath(dirs[target], dirs[name])
            lock_path.write_text(json.dumps({"version": 7, "root": "root", "nodes": {
                "root": {"inputs": {"dependency": "dependency"}},
                "dependency": {"original": {"type": "path", "path": relative}},
            }}))
        calls = []
        candidate = Candidate(self.trusted, self.candidate, self.output,
                               run=lambda argv, **kwargs: calls.append(argv))
        with self.assertRaisesRegex(Blocked, "cycle in canonical local path inputs"):
            candidate._path_parents({"canonical_locks": list(paths.values())})
        self.assertEqual(calls, [])

    def test_cli_writes_noop_artifact_without_changed_files(self):
        def fake_run(instance, argv, *, cwd):
            if argv[1] == "run":
                return None
            output = Path(argv[argv.index("--output-lock-file") + 1])
            flake_ref = argv[argv.index("--flake") + 1]
            rel = "flake.lock" if "?dir=." in flake_ref else CHILD
            output.write_bytes((self.candidate / rel).read_bytes())

        with mock.patch("maintenance.candidate.Candidate._run", autospec=True, side_effect=fake_run):
            self.assertEqual(main(["generate", "--trusted", str(self.trusted), "--candidate", str(self.candidate),
                                   "--output", str(self.output)]), 0)
        artifact = json.loads(self.output.read_text())
        self.assertTrue(artifact["noop"])
        self.assertEqual(artifact["files"], [])

    def test_unsafe_candidate_change_is_rejected(self):
        (self.candidate / "README.md").write_text("outside policy\n")
        runner, _ = self.runner(update=False)
        with self.assertRaisesRegex(Blocked, "protected paths"):
            Candidate(self.trusted, self.candidate, self.output, run=runner).generate()

    def test_failed_updater_never_writes_success_artifact(self):
        runner, _ = self.runner(fail=True)
        self.output.write_text("stale success artifact")
        with mock.patch("maintenance.candidate.Candidate._run", side_effect=Blocked("updater failed")):
            with self.assertRaises(SystemExit):
                main(["generate", "--trusted", str(self.trusted), "--candidate", str(self.candidate), "--output", str(self.output)])
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
