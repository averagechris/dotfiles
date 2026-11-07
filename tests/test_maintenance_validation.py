import hashlib
import importlib.util
import json
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/maintenance/validate.py"
spec = importlib.util.spec_from_file_location("maintenance_validate", SCRIPT)
validate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validate)


class MaintenanceValidationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.trusted = self.root / "trusted"
        self.candidate = self.root / "candidate"
        self.trusted.mkdir()
        self.candidate.mkdir()
        (self.trusted / "maintenance").mkdir()
        (self.trusted / "scripts").mkdir()
        (self.trusted / "maintenance/policy.json").write_text(json.dumps({
            "schema": 1,
            "repository": "averagechris/dotfiles",
            "required_systems": ["x86_64-linux"],
            "native_hosts": {"x86_64-linux": ["thorny"]},
            "holds": {},
        }))
        (self.candidate / "flake.lock").write_text("{}")
        self.identity_path = self.root / "identity.json"
        policy_hash = hashlib.sha256((self.trusted / "maintenance/policy.json").read_bytes()).hexdigest()
        self.identity = {
            "schema": 1,
            "repository": "averagechris/dotfiles",
            "pr": 7,
            "base": "a" * 40,
            "head": "b" * 40,
            "policy_sha256": policy_hash,
        }
        self.identity_path.write_text(json.dumps(self.identity))
        self.output = self.root / "evidence.json"

    def tearDown(self):
        self.tmp.cleanup()

    def make_validator(self, command, **kwargs):
        return validate.Validator(
            self.trusted, self.candidate, "x86_64-linux", self.identity_path,
            self.output, command=command, **kwargs,
        )

    def command_ok(self, argv, **_kwargs):
        if argv[0] == "git" and "rev-parse" in argv:
            return 0, self.identity["base"] if Path(argv[2]).name == self.trusted.name else self.identity["head"]
        if argv[0] == "nix" and "--expr" in argv:
            return 0, "x86_64-linux"
        return 0, ""

    def test_identity_policy_hash_mismatch_fails_closed(self):
        self.identity["policy_sha256"] = "0" * 64
        self.identity_path.write_text(json.dumps(self.identity))
        validator = self.make_validator(self.command_ok)
        evidence = validator.execute()
        self.assertEqual(evidence["status"], "failed")
        self.assertIn("policy SHA-256", evidence["error"])
        self.assertTrue(self.output.is_file())

    def test_candidate_commit_sha_mismatch_fails_closed(self):
        def wrong_head(argv, **_kwargs):
            if argv[0] == "git" and "rev-parse" in argv:
                return 0, "f" * 40 if Path(argv[2]).name == self.candidate.name else self.identity["base"]
            return 0, ""
        validator = self.make_validator(wrong_head)
        with self.assertRaisesRegex(validate.ValidationError, "candidate checkout HEAD"):
            validator._check_identity()

    def test_dirty_candidate_fails_closed(self):
        def dirty(argv, **_kwargs):
            if argv[0] == "git" and "rev-parse" in argv:
                return 0, self.identity["base"] if Path(argv[2]).name == self.trusted.name else self.identity["head"]
            if argv[0] == "git" and "status" in argv:
                return 0, " M flake.nix"
            return 0, ""
        validator = self.make_validator(dirty)
        with self.assertRaisesRegex(validate.ValidationError, "not clean"):
            validator._check_identity()

    def test_wrong_native_architecture_fails_closed(self):
        def command(argv, **_kwargs):
            if argv[0] == "git" and "rev-parse" in argv:
                return 0, self.identity["base"] if Path(argv[2]).name == self.trusted.name else self.identity["head"]
            if argv[0] == "nix" and "--expr" in argv:
                return 0, "aarch64-darwin"
            return 0, ""
        validator = self.make_validator(command)
        policy, _ = validator._check_identity()
        with self.assertRaisesRegex(validate.ValidationError, "architecture mismatch"):
            validator._verify_native(policy)

    def test_native_system_query_uses_trusted_cwd_only(self):
        seen = {}
        def command(argv, **kwargs):
            seen.update(argv=argv, cwd=kwargs.get("cwd"))
            return 0, "x86_64-linux"
        validator = self.make_validator(command)
        validator._verify_native({"required_systems": ["x86_64-linux"], "native_hosts": {"x86_64-linux": ["thorny"]}})
        self.assertEqual(Path(seen["cwd"]), self.trusted.resolve())
        self.assertIn("--impure", seen["argv"])
        self.assertEqual(seen["argv"][seen["argv"].index("--expr") + 1], "builtins.currentSystem")

    def test_opencode_node_modules_is_forced_to_rebuild(self):
        validator = self.make_validator(self.command_ok)
        validator._validate_flake(["thorny"])
        opencode = validator.commands[-1]["argv"]
        self.assertIn("--rebuild", opencode)
        self.assertTrue(any("nixosConfigurations.thorny.config.system.build.toplevel" in arg for cmd in validator.commands for arg in cmd["argv"]))

    def test_darwin_hold_leaves_linux_system_bundle_unattested(self):
        validator = validate.Validator(
            self.trusted, self.candidate, "aarch64-darwin", self.identity_path,
            self.output, command=self.command_ok,
        )
        package = self.root / "fake-cacert"
        bundle = package / "etc/ssl/certs/ca-bundle.crt"
        bundle.parent.mkdir(parents=True)
        bundle.write_text("certificate fixture")
        validator._resolve_locked_input = lambda _lock, _name: {"locked": {"rev": "f" * 40}}
        validator._nix = lambda *args, **_kwargs: "1.2.3" if "cacert" in args[-1] else "0.13.4"
        validator._build_path = lambda attr, **_kwargs: str(package) if "cacert" in attr else "/nix/store/test-curl"
        validator._require_openssl_curl = lambda _curl: None
        validator._curl_bundle = lambda _bundle, _hold, _curl: None
        validator._probe_uv_system_certs = lambda _uv, _python: None
        policy = {"holds": {"emudhra": {
            "input": "nixpkgs", "revision": "e" * 40,
            "minimum_versions": {"cacert": "1.2.3", "uv": "0.13.4"},
            "required_nixpkgs_commits": ["d" * 40],
        }}}
        validator.identity["ancestry"] = {"emudhra": {
            "revision": "f" * 40, "required_commits": ["d" * 40], "verified": True,
        }}
        validator._check_hold(policy, ["suremac"], {"unused": True})
        holds = validator.holds["emudhra"]
        self.assertTrue(holds["versions"])
        self.assertTrue(holds["ancestry"])
        self.assertTrue(holds["package-bundle"])
        self.assertFalse(holds["system-bundle"])
        self.assertTrue(holds["uv-system-certs"])
        self.assertIn("separate required gate", holds["details"]["state"])

    def test_linux_uv_sandbox_mounts_only_store_and_probe_inputs(self):
        validator = self.make_validator(self.command_ok)
        validator._build_path = lambda _attr, **_kwargs: "/nix/store/test-bubblewrap"
        probe = self.root / "probe-inputs"
        scratch = self.root / "uv-scratch"
        prefix, trust_ca, untrusted_ca, _env = validator._uv_sandbox(probe, scratch)
        self.assertIn("--share-net", prefix)
        self.assertIn("--unshare-pid", prefix)
        self.assertIn("--ro-bind", prefix)
        self.assertIn("/nix/store", prefix)
        self.assertIn(str(probe.resolve()), prefix)
        self.assertEqual((trust_ca, untrusted_ca), ("/probe/local-ca.pem", "/probe/untrusted-ca.pem"))
        self.assertNotIn(str(self.trusted), prefix)
        self.assertNotIn(str(self.candidate), prefix)
        self.assertNotIn(str(self.output.parent), prefix)
        self.assertIn("--tmpfs", prefix)

    def test_darwin_sandbox_uses_profile_file_and_denies_user_home(self):
        validator = validate.Validator(self.trusted, self.candidate, "aarch64-darwin", self.identity_path, self.output, command=self.command_ok)
        probe = self.root / "probe-inputs"
        probe.mkdir()
        scratch = self.root / "scratch"
        with patch.object(Path, "is_file", return_value=True):
            prefix, _trusted, _untrusted, _env = validator._uv_sandbox(probe, scratch)
        self.assertEqual(prefix[1], "-f")
        profile = Path(prefix[2]).read_text()
        self.assertIn('(deny file-read* (subpath "/Users"))', profile)
        self.assertIn('(deny file-read* (subpath "/etc/nix"))', profile)
        self.assertIn('(deny file-read* (subpath "/private/var/folders"))', profile)
        self.assertIn(f'(allow file-write* (subpath "{scratch.resolve()}"))', profile)
        self.assertIn('(allow network-outbound (remote ip "localhost:*"))', profile)
        self.assertNotIn(str(self.trusted), profile)
        self.assertNotIn(str(self.candidate), profile)

    def test_certificate_network_error_is_not_a_rejection_pass(self):
        validator = self.make_validator(lambda argv, **_kwargs: (35, "TLS connect error"))
        hold = {"reject_endpoints": ["https://reject.invalid/", "https://reject2.invalid/"], "healthy_endpoint": "https://healthy.invalid/"}
        curl = Path("/nix/store/test-curl/bin/curl")
        validator._require_openssl_curl = lambda _curl: None
        with self.assertRaisesRegex(validate.ValidationError, "expected 60"):
            validator._curl_bundle("/tmp/candidate.pem", hold, curl)
        self.assertEqual(validator.commands[0]["expected_exit_code"], 60)
        self.assertEqual(validator.commands[0]["exit_code"], 35)

    def test_healthy_control_must_succeed(self):
        codes = iter([60, 60, 7])
        validator = self.make_validator(lambda argv, **_kwargs: (next(codes), "curl result"))
        hold = {"reject_endpoints": ["https://reject.invalid/", "https://reject2.invalid/"], "healthy_endpoint": "https://healthy.invalid/"}
        validator._require_openssl_curl = lambda _curl: None
        with self.assertRaisesRegex(validate.ValidationError, "expected 0"):
            validator._curl_bundle("/tmp/candidate.pem", hold, Path("/nix/store/test-curl/bin/curl"))

    def test_curl_probe_uses_explicit_executable_and_requires_openssl(self):
        seen = []
        validator = self.make_validator(lambda argv, **_kwargs: (seen.append(argv) or 0, "libcurl/8.22.0 OpenSSL/3.5.9"))
        curl = Path("/nix/store/hash-curl/bin/curl")
        with patch.object(Path, "is_file", return_value=True), patch.object(validate.os, "access", return_value=True):
            validator._require_openssl_curl(curl)
        self.assertEqual(seen, [[str(curl), "--version"]])
        validator.command = lambda argv, **_kwargs: (0, "libcurl/8.7.1 SecureTransport")
        with patch.object(Path, "is_file", return_value=True), patch.object(validate.os, "access", return_value=True):
            with self.assertRaisesRegex(validate.ValidationError, "OpenSSL TLS backend"):
                validator._require_openssl_curl(curl)

    def test_missing_ancestry_proof_fails_closed(self):
        validator = self.make_validator(self.command_ok)
        hold = {"revision": "e" * 40, "required_nixpkgs_commits": ["d" * 40]}
        with self.assertRaisesRegex(validate.ValidationError, "no verified ancestry proof"):
            validator._verify_ancestry_proof("emudhra", hold, "f" * 40)

    def test_mismatched_ancestry_proof_fails_closed(self):
        validator = self.make_validator(self.command_ok)
        hold = {"revision": "e" * 40, "required_nixpkgs_commits": ["d" * 40]}
        validator.identity["ancestry"] = {"emudhra": {
            "revision": "c" * 40, "required_commits": ["d" * 40], "verified": True,
        }}
        with self.assertRaisesRegex(validate.ValidationError, "revision does not match"):
            validator._verify_ancestry_proof("emudhra", hold, "f" * 40)

    def test_ancestry_proof_must_match_policy_commits(self):
        validator = self.make_validator(self.command_ok)
        hold = {"revision": "e" * 40, "required_nixpkgs_commits": ["d" * 40]}
        validator.identity["ancestry"] = {"emudhra": {
            "revision": "f" * 40, "required_commits": ["c" * 40], "verified": True,
        }}
        with self.assertRaisesRegex(validate.ValidationError, "commits do not match policy"):
            validator._verify_ancestry_proof("emudhra", hold, "f" * 40)

    def test_eval_stdout_is_separate_from_retained_stderr_warnings(self):
        validator = self.make_validator(lambda _argv, **_kwargs: validate.CommandResult(0, "3.131.1", "warning: from evaluator\n"))
        output = validator.run(["nix", "eval", "--raw", "package.version"])
        self.assertEqual(output, "3.131.1")
        log = (self.output.with_name(self.output.name + ".logs") / "001.log").read_text()
        self.assertIn("warning: from evaluator", log)
        self.assertEqual(validator.commands[0]["log_sha256"], hashlib.sha256(log.encode()).hexdigest())

    def test_all_nix_commands_disable_lock_mutation_and_sandbox(self):
        validator = self.make_validator(self.command_ok)
        validator._nix("flake", "check", "--system", "x86_64-linux")
        argv = validator.commands[-1]["argv"]
        self.assertIn("--no-update-lock-file", argv)
        self.assertIn("--no-write-lock-file", argv)
        self.assertEqual(argv[argv.index("--option") + 1:argv.index("--option") + 3], ["sandbox", "true"])
        self.assertEqual(validator.commands[-1]["expected_exit_code"], 0)

    def test_warning_comparison_captures_base_and_new_candidate_warnings(self):
        logs = iter(["warning: old baseline warning\n", "warning: old baseline warning\nwarning: new candidate warning\n"])
        validator = self.make_validator(lambda argv, **_kwargs: validate.CommandResult(0, "", next(logs)))
        with self.assertRaisesRegex(validate.ValidationError, "introduced flake evaluation warnings"):
            validator._compare_flake_warnings()
        self.assertEqual(validator.warning_comparison["baseline"], ["warning: old baseline warning"])
        self.assertEqual(validator.warning_comparison["candidate"], ["warning: new candidate warning", "warning: old baseline warning"])
        self.assertEqual(validator.warning_comparison["new"], ["warning: new candidate warning"])
        self.assertEqual(len(validator.commands), 2)
        self.assertTrue(all((self.output.with_name(self.output.name + ".logs") / f"{i:03d}.log").is_file() for i in (1, 2)))

    def test_failed_execution_always_writes_evidence_with_command_hashes(self):
        def fail_check(argv, **_kwargs):
            if argv[0] == "git" and "rev-parse" in argv:
                return 0, self.identity["base"] if Path(argv[2]).name == self.trusted.name else self.identity["head"]
            if argv[0] == "nix" and "--expr" in argv:
                return 0, "x86_64-linux"
            if argv[0] == "nix" and "check" in argv:
                return 1, "fixture check failure"
            return 0, ""
        validator = self.make_validator(fail_check)
        evidence = validator.execute()
        self.assertEqual(evidence["status"], "failed")
        self.assertTrue(self.output.is_file())
        self.assertTrue(evidence["commands"])
        for command in evidence["commands"]:
            self.assertEqual(len(command["log_sha256"]), 64)
            self.assertIn("exit_code", command)
        self.assertTrue(list(self.output.with_name(self.output.name + ".logs").glob("*.log")))


if __name__ == "__main__":
    unittest.main()
