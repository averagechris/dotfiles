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


def self_deploy_activation_snippet() -> str:
    source = MODULE.read_text()
    match = re.search(
        r"(?ms)^      system_profile=/nix/var/nix/profiles/system$.*?^      exit 1\n    '';",
        source,
    )
    if not match:
        raise AssertionError("Could not find activation/rollback block in self-deploy module")
    return "\n".join(
        line[6:] if line.startswith("      ") else line
        for line in match.group().splitlines()[:-1]
    ).replace("${hostName}", "testhost")


class SelfDeployRevisionPinTests(unittest.TestCase):
    def run_snippet(
        self, metadata: dict, *, valid_previous_system: bool = True
    ) -> tuple[subprocess.CompletedProcess, str, str]:
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
            previous_system = temp / "previous-system"
            if valid_previous_system:
                (previous_system / "bin").mkdir(parents=True)
                previous_switch = previous_system / "bin/switch-to-configuration"
                previous_switch.write_text(f"#!{sh}\nexit 0\n")
                previous_switch.chmod(0o755)
            (fake_bin / "readlink").write_text(
                f"#!{sh}\nprintf '%s\\n' \"$PREVIOUS_SYSTEM\"\n"
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
                "PREVIOUS_SYSTEM": str(previous_system),
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

    def test_invalid_previous_closure_fails_before_build(self):
        metadata = {"revision": REV_A, "locked": {"rev": REV_A}, "lockedUrl": LOCKED_URL_A}
        result, build_ref, _ = self.run_snippet(metadata, valid_previous_system=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(build_ref, "")
        self.assertIn("unavailable or invalid", result.stderr)

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
        self.assertEqual(
            build_ref,
            f"github:example/dotfiles/{REV_A}#nixosConfigurations.testhost.config.system.build.toplevel",
        )

    def test_github_shorthand_accepts_query_after_revision(self):
        metadata = {"revision": REV_A, "locked": {"rev": REV_A},
                    "lockedUrl": f"github:example/dotfiles/{REV_A}?narHash=sha256-test"}
        result, build_ref, _ = self.run_snippet(metadata)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            build_ref,
            f"github:example/dotfiles/{REV_A}?narHash=sha256-test#nixosConfigurations.testhost.config.system.build.toplevel",
        )

    def test_duplicate_revision_query_parameters_are_rejected(self):
        metadata = {"revision": REV_A, "locked": {"rev": REV_A},
                    "lockedUrl": f"git+https://example.invalid/dotfiles?rev={REV_A}&rev={REV_A}"}
        result, build_ref, _ = self.run_snippet(metadata)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(build_ref, "")


class SelfDeployActivationTests(unittest.TestCase):
    def run_activation(self, *, new_activation_fails=False, health_fails=False):
        with tempfile.TemporaryDirectory() as tmp:
            temp = Path(tmp)
            fake_bin = temp / "bin"
            fake_bin.mkdir()
            bash = shutil.which("bash")
            sh = shutil.which("sh")
            self.assertIsNotNone(bash, "bash must be available on PATH")
            self.assertIsNotNone(sh, "sh must be available on PATH")
            previous_system = temp / "previous-system"
            new_system = temp / "new-system"
            for system, exit_status in (
                (previous_system, 0),
                (new_system, int(new_activation_fails)),
            ):
                (system / "bin").mkdir(parents=True)
                switch = system / "bin/switch-to-configuration"
                switch.write_text(
                    f"#!{sh}\nprintf '%s\\n' '{system.name}-switch' >>\"$EVENTS\"\nexit {exit_status}\n"
                )
                switch.chmod(0o755)
            events = temp / "events"
            fake_nix_env = fake_bin / "nix-env"
            fake_nix_env.write_text(
                f"#!{sh}\nprintf 'profile:%s\\n' \"$4\" >>\"$EVENTS\"\n"
            )
            fake_nix_env.chmod(0o755)
            state_dir = temp / "state"
            state_dir.mkdir()
            script = "\n".join(
                [
                    f"#!{bash}",
                    "set -euo pipefail",
                    f"previous_system={shlex.quote(str(previous_system))}",
                    f"new_system={shlex.quote(str(new_system))}",
                    f"latest_rev={shlex.quote(REV_A)}",
                    f"last_failure_rev_file={shlex.quote(str(state_dir / 'last-failure-rev'))}",
                    f"last_success_rev_file={shlex.quote(str(state_dir / 'last-success-rev'))}",
                    "health_check() { printf 'health\\n' >>\"$EVENTS\"; return \"$HEALTH_STATUS\"; }",
                    self_deploy_activation_snippet(),
                ]
            )
            script_path = temp / "test-activation.sh"
            script_path.write_text(script)
            env = os.environ | {
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
                "EVENTS": str(events),
                "HEALTH_STATUS": str(int(health_fails)),
            }
            result = subprocess.run([bash, str(script_path)], capture_output=True, text=True, env=env)
            return result, events.read_text().splitlines() if events.exists() else []

    def test_sets_profile_before_activation(self):
        result, events = self.run_activation()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            events,
            ["profile:" + str(Path(result.args[1]).parent / "new-system"), "new-system-switch", "health"],
        )

    def test_activation_failure_restores_profile_before_previous_activation(self):
        result, events = self.run_activation(new_activation_fails=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(
            events,
            [
                "profile:" + str(Path(result.args[1]).parent / "new-system"),
                "new-system-switch",
                "profile:" + str(Path(result.args[1]).parent / "previous-system"),
                "previous-system-switch",
            ],
        )

    def test_health_failure_restores_profile_before_rollback_and_checks_health(self):
        result, events = self.run_activation(health_fails=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(
            events[:4],
            [
                "profile:" + str(Path(result.args[1]).parent / "new-system"),
                "new-system-switch",
                "health",
                "profile:" + str(Path(result.args[1]).parent / "previous-system"),
            ],
        )
        self.assertEqual(events[4:], ["previous-system-switch", "health"])


if __name__ == "__main__":
    unittest.main()
