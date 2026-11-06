#!/usr/bin/env python3
"""Regression tests for the revision-resolution/build portion of self-deploy."""

import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "flakes/nixos-modules/modules/self-deploy.nix"
REV_A = "a" * 40
LOCKED_URL_A = f"git+https://example.invalid/dotfiles?ref=main&rev={REV_A}"


def self_deploy_build_snippet() -> str:
    source = MODULE.read_text()
    match = re.search(
        r"(?ms)^      metadata_json=\$\(nix flake metadata.*?^      echo \"New system: \$new_system\"$",
        source,
    )
    if not match:
        raise AssertionError("Could not find metadata/build block in self-deploy module")
    return match.group().replace("${hostName}", "testhost")


class SelfDeployRevisionPinTests(unittest.TestCase):
    def run_snippet(self, metadata: dict) -> tuple[subprocess.CompletedProcess, str, str]:
        with tempfile.TemporaryDirectory() as tmp:
            temp = Path(tmp)
            fake_bin = temp / "bin"
            fake_bin.mkdir()
            bash = shutil.which("bash")
            sh = shutil.which("sh")
            self.assertIsNotNone(bash, "bash must be available on PATH")
            self.assertIsNotNone(sh, "sh must be available on PATH")
            (fake_bin / "nix").write_text(
                f"#!{bash}\n"
                'if [ "$1" = flake ] && [ "$2" = metadata ]; then\n'
                '  printf \'%s\\n\' "$METADATA_JSON"\n'
                '  printf B >"$BRANCH_STATE"\n'
                'elif [ "$1" = build ]; then\n'
                '  printf \'%s\\n\' "${!#}" >"$BUILD_REF"\n'
                '  printf \'%s\\n\' /nix/store/test-system\n'
                'else\n'
                '  exit 99\n'
                'fi\n'
            )
            (fake_bin / "nix").chmod(0o755)
            (fake_bin / "readlink").write_text(
                f"#!{sh}\nprintf /nix/store/previous-system\n"
            )
            (fake_bin / "readlink").chmod(0o755)
            state_dir = temp / "state"
            script = "\n".join(
                [
                    f"#!{bash}",
                    "set -euo pipefail",
                    f"state_dir={shlex.quote(str(state_dir))}",
                    'lock_file="$state_dir/deploy.lock"',
                    'last_success_rev_file="$state_dir/last-success-rev"',
                    'last_attempt_rev_file="$state_dir/last-attempt-rev"',
                    'last_failure_rev_file="$state_dir/last-failure-rev"',
                    'flake_ref="git+https://example.invalid/dotfiles?ref=main"',
                    'attr="nixosConfigurations.testhost.config.system.build.toplevel"',
                    'mkdir -p "$state_dir"',
                    self_deploy_build_snippet(),
                ]
            )
            script_path = temp / "test.sh"
            script_path.write_text(script)
            build_ref = temp / "build-ref"
            branch_state = temp / "branch-state"
            env = os.environ | {
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
                "METADATA_JSON": json.dumps(metadata),
                "BUILD_REF": str(build_ref),
                "BRANCH_STATE": str(branch_state),
            }
            result = subprocess.run(
                [bash, str(script_path)], capture_output=True, text=True, env=env
            )
            return result, build_ref.read_text().strip() if build_ref.exists() else "", branch_state.read_text() if branch_state.exists() else ""

    def test_build_uses_revision_resolved_before_branch_moves(self):
        metadata = {
            "revision": REV_A,
            "locked": {"rev": REV_A},
            "lockedUrl": LOCKED_URL_A,
        }
        result, build_ref, branch_state = self.run_snippet(metadata)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(branch_state, "B", "fake metadata lookup should move main to B")
        self.assertEqual(
            build_ref,
            f"{LOCKED_URL_A}#nixosConfigurations.testhost.config.system.build.toplevel",
        )
        self.assertIn("at " + REV_A, result.stdout)

    def test_missing_or_malformed_revision_fails_before_build(self):
        for revision in (None, "main", "a" * 39):
            with self.subTest(revision=revision):
                metadata = {"revision": revision, "lockedUrl": LOCKED_URL_A}
                result, build_ref, _ = self.run_snippet(metadata)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(build_ref, "")
                self.assertIn("valid locked revision", result.stderr)

    def test_missing_locked_url_fails_before_build(self):
        result, build_ref, _ = self.run_snippet({"revision": REV_A, "locked": {"rev": REV_A}})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(build_ref, "")
        self.assertIn("locked flake URL", result.stderr)

    def test_mutable_legacy_url_is_rejected_without_locked_url(self):
        metadata = {"revision": REV_A, "locked": {"rev": REV_A},
                    "url": "git+https://example.invalid/dotfiles?ref=main"}
        result, build_ref, _ = self.run_snippet(metadata)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(build_ref, "")
        self.assertIn("not pinned", result.stderr)

    def test_mismatched_locked_url_and_malformed_fragment_are_rejected(self):
        for value in (f"git+https://example.invalid/dotfiles?ref=main&rev={'b' * 40}",
                      LOCKED_URL_A + "#bad"):
            with self.subTest(value=value):
                metadata = {"revision": REV_A, "locked": {"rev": REV_A}, "lockedUrl": value}
                result, build_ref, _ = self.run_snippet(metadata)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(build_ref, "")

    def test_old_github_shorthand_url_is_accepted_when_it_contains_revision(self):
        metadata = {"revision": REV_A, "locked": {"rev": REV_A},
                    "url": f"github:example/dotfiles/{REV_A}"}
        result, build_ref, _ = self.run_snippet(metadata)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(build_ref, f"github:example/dotfiles/{REV_A}#nixosConfigurations.testhost.config.system.build.toplevel")


if __name__ == "__main__":
    unittest.main()
