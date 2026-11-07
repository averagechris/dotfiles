#!/usr/bin/env python3
"""Trusted native validation for an untrusted maintenance candidate."""
from __future__ import annotations

import argparse
import hashlib
import http.server
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import threading
import time
import uuid
import zipfile
from pathlib import Path
from typing import Any, Callable

POLICY_REL = Path("maintenance/policy.json")
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
DEFAULT_TIMEOUT = 3600
MAX_LOG_BYTES = 2_000_000
MAX_WARNINGS = 40


class ValidationError(RuntimeError):
    pass


class CommandResult:
    def __init__(self, exit_code: int, stdout: str, stderr: str = ""):
        self.exit_code = exit_code
        self.stdout = stdout
        self.stderr = stderr


def _json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValidationError(f"cannot read valid JSON at {path}: {exc}") from exc


def _safe_environment() -> dict[str, str]:
    # Candidate evaluation and builds receive no inherited credentials or
    # user Nix configuration. Keep only process/platform basics.
    allowed = ("PATH", "HOME", "TMPDIR", "TMP", "TEMP", "USER", "LOGNAME", "LANG", "LC_ALL", "TERM", "SSL_CERT_FILE", "NIX_REMOTE")
    env = {key: os.environ[key] for key in allowed if key in os.environ}
    env["NIX_USER_CONF_FILES"] = "/dev/null"
    env["NIX_CONFIG"] = "sandbox = true\naccept-flake-config = false\nextra-substituters = \n"
    return env


class Validator:
    def __init__(
        self,
        trusted: Path,
        candidate: Path,
        system: str,
        identity_path: Path,
        output: Path,
        *,
        command: Callable[..., Any] | None = None,
        timeout: int = DEFAULT_TIMEOUT,
    ) -> None:
        self.trusted = trusted.resolve()
        self.candidate = candidate.resolve()
        self.system = system
        self.identity_path = identity_path
        self.output = output
        self.command = command or self._command
        self.timeout = timeout
        self.commands: list[dict[str, Any]] = []
        self.warnings: list[str] = []
        self.last_stderr = ""
        self.warning_comparison: dict[str, Any] = {"baseline": [], "candidate": [], "new": []}
        self.holds = {
            "emudhra": {
                "versions": False,
                "ancestry": False,
                "package-bundle": False,
                "system-bundle": False,
                "uv-system-certs": False,
                "details": {},
            }
        }
        self.identity: dict[str, Any] = {}

    def _command(self, argv: list[str], cwd: Path | None = None, timeout: int | None = None, env_overrides: dict[str, str] | None = None) -> CommandResult:
        env = _safe_environment()
        env.update(env_overrides or {})
        try:
            result = subprocess.run(
                argv,
                cwd=cwd,
                env=env,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=timeout or self.timeout,
                check=False,
            )
            return CommandResult(result.returncode, result.stdout, result.stderr)
        except subprocess.TimeoutExpired as exc:
            stdout = exc.stdout or ""
            stderr = exc.stderr or ""
            if isinstance(stdout, bytes):
                stdout = stdout.decode("utf-8", errors="replace")
            if isinstance(stderr, bytes):
                stderr = stderr.decode("utf-8", errors="replace")
            return CommandResult(124, stdout, f"command timed out after {timeout or self.timeout}s\n{stderr}")
        except OSError as exc:
            return CommandResult(127, "", f"could not execute command: {exc}")

    def run(
        self,
        argv: list[str],
        *,
        cwd: Path | None = None,
        timeout: int | None = None,
        check: bool = True,
        expected_exit_code: int = 0,
        env_overrides: dict[str, str] | None = None,
    ) -> str:
        result = self.command(argv, cwd=cwd, timeout=timeout or self.timeout, env_overrides=env_overrides)
        if isinstance(result, CommandResult):
            exit_code, stdout, stderr = result.exit_code, result.stdout, result.stderr
        else:  # Compatibility seam for compact unit-test command fakes.
            exit_code, stdout = result
            stderr = ""
        self.last_stderr = stderr
        log_bytes = (stdout + ("\n[stderr]\n" + stderr if stderr else "")).encode("utf-8", errors="replace")[-MAX_LOG_BYTES:]
        entry = {
            "argv": argv,
            "cwd": str((cwd or Path.cwd()).resolve()),
            "exit_code": exit_code,
            "expected_exit_code": expected_exit_code,
            "log_sha256": hashlib.sha256(log_bytes).hexdigest(),
        }
        self.commands.append(entry)
        self._write_log(len(self.commands), log_bytes)
        if check and exit_code != expected_exit_code:
            raise ValidationError(f"command failed ({exit_code}, expected {expected_exit_code}): {' '.join(argv)}")
        return stdout

    def _write_log(self, index: int, payload: bytes) -> None:
        log_dir = self.output.with_name(self.output.name + ".logs")
        log_dir.mkdir(parents=True, exist_ok=True)
        (log_dir / f"{index:03d}.log").write_bytes(payload)

    def _git(self, root: Path, *args: str) -> str:
        return self.run(["git", "-C", str(root), *args]).strip()

    def _check_identity(self) -> tuple[dict[str, Any], dict[str, Any]]:
        policy_path = self.trusted / POLICY_REL
        policy_bytes = policy_path.read_bytes()
        policy_hash = hashlib.sha256(policy_bytes).hexdigest()
        policy = json.loads(policy_bytes)
        identity = _json(self.identity_path)
        if isinstance(identity, dict):
            self.identity = {key: identity[key] for key in ("schema", "repository", "pr", "base", "head", "policy_sha256", "ancestry") if key in identity}
        if not isinstance(identity, dict) or identity.get("schema") != 1:
            raise ValidationError("identity schema must be 1")
        if identity.get("repository") != policy.get("repository"):
            raise ValidationError("identity repository does not match trusted policy")
        for field in ("base", "head"):
            value = identity.get(field)
            if not isinstance(value, str) or not SHA_RE.fullmatch(value):
                raise ValidationError(f"identity {field} must be a lowercase 40-character commit SHA")
        if identity.get("policy_sha256") != policy_hash:
            raise ValidationError("trusted policy SHA-256 does not match identity")
        if not isinstance(identity.get("pr"), (str, int)):
            raise ValidationError("identity pr is missing")
        trusted_head = self._git(self.trusted, "rev-parse", "HEAD")
        candidate_head = self._git(self.candidate, "rev-parse", "HEAD")
        if trusted_head != identity["base"]:
            raise ValidationError("trusted checkout HEAD does not equal identity base")
        if candidate_head != identity["head"]:
            raise ValidationError("candidate checkout HEAD does not equal identity head")
        dirty = self._git(self.candidate, "status", "--porcelain=v1", "--untracked-files=all")
        if dirty:
            raise ValidationError("candidate checkout is not clean")
        return policy, identity

    def _nix(self, *args: str, cwd: Path | None = None, check: bool = True) -> str:
        argv = ["nix", *args, "--no-update-lock-file", "--no-write-lock-file", "--option", "sandbox", "true"]
        return self.run(argv, cwd=cwd or self.candidate, check=check)

    def _resolve_locked_input(self, lock: dict[str, Any], name: str) -> dict[str, Any]:
        nodes = lock["nodes"]

        def resolve_ref(ref: Any) -> dict[str, Any]:
            if isinstance(ref, list):
                if not ref:
                    raise ValidationError(f"empty flake lock input route for {name}")
                node = resolve_ref(ref[0])
                for child in ref[1:]:
                    node_id = node.get("inputs", {}).get(child)
                    node = resolve_ref(node_id)
                return node
            if not isinstance(ref, str) or ref not in nodes:
                raise ValidationError(f"cannot resolve locked flake input {name}")
            return nodes[ref]

        root_inputs = nodes[lock["root"]]["inputs"]
        if name not in root_inputs:
            raise ValidationError(f"candidate flake.lock has no {name} input")
        return resolve_ref(root_inputs[name])

    def _verify_native(self, policy: dict[str, Any]) -> list[str]:
        if self.system not in policy.get("required_systems", []):
            raise ValidationError(f"system {self.system} is not required by trusted policy")
        hosts = policy.get("native_hosts", {}).get(self.system)
        if not isinstance(hosts, list) or not hosts:
            raise ValidationError(f"no native hosts are configured for {self.system}")
        actual = self.run(
            ["nix", "eval", "--impure", "--raw", "--expr", "builtins.currentSystem", "--no-update-lock-file", "--no-write-lock-file", "--option", "sandbox", "true"],
            cwd=self.trusted,
        ).strip()
        if actual != self.system:
            raise ValidationError(f"native architecture mismatch: builtins.currentSystem={actual}, requested={self.system}")
        return hosts

    def _validate_flake(self, hosts: list[str]) -> None:
        self._nix("flake", "check", "--system", self.system)
        for host in hosts:
            if self.system == "aarch64-darwin":
                attr = f"darwinConfigurations.{host}.system"
            else:
                attr = f"nixosConfigurations.{host}.config.system.build.toplevel"
            self._nix("eval", "--raw", f".#{attr}.drvPath")
            self._nix("build", "--no-link", f".#{attr}")
        representative = hosts[0]
        opencode = f"nixosConfigurations.{representative}.pkgs.opencode.node_modules"
        if self.system == "aarch64-darwin":
            opencode = f"darwinConfigurations.{representative}.pkgs.opencode.node_modules"
        self._nix("build", "--rebuild", "--no-link", f".#{opencode}")

    @staticmethod
    def _warning_lines(log: str) -> list[str]:
        return sorted({line.strip()[:1000] for line in log.splitlines() if "warning:" in line.lower()})

    def _compare_flake_warnings(self) -> None:
        base_log = self._nix("flake", "check", "--no-build", "--system", self.system, cwd=self.trusted) + self.last_stderr
        candidate_log = self._nix("flake", "check", "--no-build", "--system", self.system, cwd=self.candidate) + self.last_stderr
        baseline = self._warning_lines(base_log)
        candidate = self._warning_lines(candidate_log)
        new = sorted(set(candidate) - set(baseline))
        self.warning_comparison = {
            "baseline": baseline[:MAX_WARNINGS],
            "candidate": candidate[:MAX_WARNINGS],
            "new": new[:MAX_WARNINGS],
        }
        self.warnings.extend(new)
        if new:
            raise ValidationError(f"candidate introduced flake evaluation warnings: {'; '.join(new[:4])}")

    def _verify_ancestry_proof(self, hold_name: str, hold: dict[str, Any], candidate_rev: str) -> None:
        commits = hold.get("required_nixpkgs_commits") or [hold["revision"]]
        ancestry = self.identity.get("ancestry")
        proof = ancestry.get(hold_name) if isinstance(ancestry, dict) else None
        if not isinstance(proof, dict) or proof.get("verified") is not True:
            raise ValidationError(f"trusted identity has no verified ancestry proof for hold {hold_name}")
        if proof.get("revision") != candidate_rev:
            raise ValidationError(f"trusted ancestry proof revision does not match candidate nixpkgs {candidate_rev}")
        if proof.get("required_commits") != commits:
            raise ValidationError(f"trusted ancestry proof commits do not match policy for hold {hold_name}")
        if any(not isinstance(commit, str) or not SHA_RE.fullmatch(commit) for commit in commits):
            raise ValidationError("trusted hold contains invalid required nixpkgs commit")

    def _check_hold_versions(self, hold: dict[str, Any], attr_prefix: str) -> dict[str, str]:
        versions: dict[str, str] = {}
        for package, minimum in hold["minimum_versions"].items():
            actual = self._nix("eval", "--raw", f".{attr_prefix}.{package}.version")
            versions[package] = actual
            if self._version_tuple(actual) < self._version_tuple(minimum):
                raise ValidationError(f"{package} {actual} is below required {minimum}")
        return versions

    @staticmethod
    def _version_tuple(value: str) -> tuple[int, ...]:
        match = re.match(r"^(\d+(?:\.\d+)*)(?:[-+].*)?$", value)
        if not match:
            raise ValidationError(f"cannot compare package version {value!r}")
        return tuple(int(part) for part in match.group(1).split("."))

    def _check_hold(self, policy: dict[str, Any], hosts: list[str], candidate_lock: dict[str, Any]) -> None:
        hold = policy.get("holds", {}).get("emudhra")
        if not isinstance(hold, dict):
            raise ValidationError("trusted policy is missing its required eMudhra hold definition")
        node = self._resolve_locked_input(candidate_lock, hold.get("input", "nixpkgs"))
        candidate_rev = node.get("locked", {}).get("rev")
        if not isinstance(candidate_rev, str) or not SHA_RE.fullmatch(candidate_rev):
            raise ValidationError("candidate nixpkgs lock has no valid locked revision")
        self._verify_ancestry_proof("emudhra", hold, candidate_rev)
        if candidate_rev == hold["revision"]:
            for check in ("versions", "ancestry", "package-bundle", "system-bundle", "uv-system-certs"):
                self.holds["emudhra"][check] = True
            self.holds["emudhra"]["details"] = {"state": "trusted nixpkgs hold retained", "revision": candidate_rev}
            return
        if self.system == "aarch64-darwin":
            self.holds["emudhra"]["details"] = {
                "state": "system-bundle check is Linux-native; host keychain attestation is a separate required gate",
                "revision": candidate_rev,
            }
            versions = self._check_hold_versions(hold, "darwinConfigurations.suremac.pkgs")
            self.holds["emudhra"]["versions"] = True
            self.holds["emudhra"]["ancestry"] = True
            package_path = self._build_path("darwinConfigurations.suremac.pkgs.cacert")
            package_bundle = Path(package_path) / "etc/ssl/certs/ca-bundle.crt"
            if not package_bundle.is_file():
                package_bundle = Path(package_path) / "etc/ssl/certs/ca-bundle.pem"
            if not package_bundle.is_file():
                raise ValidationError("candidate Darwin cacert output contains no known CA bundle file")
            self._curl_bundle(str(package_bundle), hold)
            self.holds["emudhra"]["package-bundle"] = True
            uv_path = self._build_path("darwinConfigurations.suremac.pkgs.uv")
            uv = Path(uv_path) / "bin" / "uv"
            python_path = Path(self._build_path("darwinConfigurations.suremac.pkgs.python3")) / "bin/python3"
            self._probe_uv_system_certs(uv, python_path)
            self.holds["emudhra"]["uv-system-certs"] = True
            self.holds["emudhra"]["details"].update({"versions": versions, "package_path": package_path, "uv_path": str(uv)})
            return
        if self.system not in ("x86_64-linux", "aarch64-linux"):
            raise ValidationError(f"changed eMudhra hold is unsupported on native system {self.system}")
        host = next((name for name in hosts if name in ("thorny", "tater")), hosts[0])
        versions = self._check_hold_versions(hold, f"nixosConfigurations.{host}.pkgs")
        self.holds["emudhra"]["versions"] = True
        self.holds["emudhra"]["ancestry"] = True
        self.holds["emudhra"]["details"] = {"revision": candidate_rev, "versions": versions}
        package_path = self._build_path(f"nixosConfigurations.{host}.pkgs.cacert")
        system_path = self._build_path(f"nixosConfigurations.{host}.config.system.build.toplevel")
        bundle_log = self._nix("eval", "--raw", f".#nixosConfigurations.{host}.config.security.pki.caBundle")
        bundle = bundle_log.strip().splitlines()[-1]
        if not bundle.startswith("/nix/store/") or not Path(bundle).is_file():
            raise ValidationError("candidate system certificate bundle was not realized as a store file")
        package_bundle = Path(package_path) / "etc/ssl/certs/ca-bundle.crt"
        if not package_bundle.is_file():
            package_bundle = Path(package_path) / "etc/ssl/certs/ca-bundle.pem"
        if not package_bundle.is_file():
            raise ValidationError("candidate cacert output contains no known CA bundle file")
        self._curl_bundle(str(package_bundle), hold)
        self.holds["emudhra"]["package-bundle"] = True
        self._curl_bundle(bundle, hold)
        self.holds["emudhra"]["system-bundle"] = True
        uv_path = self._build_path(f"nixosConfigurations.{host}.pkgs.uv")
        uv = Path(uv_path) / "bin" / "uv"
        python_path = Path(self._build_path(f"nixosConfigurations.{host}.pkgs.python3")) / "bin/python3"
        self._probe_uv_system_certs(uv, python_path)
        self.holds["emudhra"]["uv-system-certs"] = True
        self.holds["emudhra"]["details"].update({"package_path": package_path, "system_path": system_path, "uv_path": str(uv)})

    def _build_path(self, attr: str, *, cwd: Path | None = None) -> str:
        result = self._nix("build", "--no-link", "--print-out-paths", f".#{attr}", cwd=cwd)
        paths = [line.strip() for line in result.splitlines() if line.strip().startswith("/nix/store/")]
        if not paths:
            raise ValidationError(f"nix build did not return an output path for {attr}")
        return paths[-1]

    def _curl_bundle(self, bundle: str, hold: dict[str, Any]) -> None:
        for endpoint in hold["reject_endpoints"]:
            self.run(
                ["curl", "--disable", "--silent", "--show-error", "--output", "/dev/null", "--max-time", "30", "--cacert", bundle, endpoint],
                timeout=45,
                expected_exit_code=60,
            )
        endpoint = hold["healthy_endpoint"]
        self.run(
            ["curl", "--disable", "--silent", "--show-error", "--output", "/dev/null", "--max-time", "30", "--cacert", bundle, endpoint],
            timeout=45,
        )

    def _probe_uv_system_certs(self, uv: Path, python: Path) -> None:
        """Prove the candidate uv binary uses SSL_CERT_FILE without opt-in."""
        import ssl

        with tempfile.TemporaryDirectory(prefix="dotfiles-uv-trust-") as temp:
            root = Path(temp)
            ca_cert = root / "local-ca.pem"
            ca_key = root / "local-ca.key"
            server_cert = root / "server.pem"
            server_key = root / "server.key"
            csr = root / "server.csr"
            config = root / "openssl.cnf"
            config.write_text(
                "[req]\ndistinguished_name=dn\nx509_extensions=v3_ca\nprompt=no\n"
                "[dn]\nCN=maintenance-local-probe\n"
                "[v3_ca]\nbasicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n"
                "[v3_server]\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\n"
                "extendedKeyUsage=serverAuth\nsubjectAltName=IP:127.0.0.1\n",
                encoding="utf-8",
            )
            self.run([
                "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                "-keyout", str(ca_key), "-out", str(ca_cert), "-config", str(config), "-extensions", "v3_ca",
            ], timeout=60)
            self.run(["openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes", "-keyout", str(server_key), "-out", str(csr), "-subj", "/CN=maintenance-local-probe"], timeout=60)
            self.run(["openssl", "x509", "-req", "-in", str(csr), "-CA", str(ca_cert), "-CAkey", str(ca_key), "-CAcreateserial", "-out", str(server_cert), "-days", "1", "-extfile", str(config), "-extensions", "v3_server"], timeout=60)
            input_dir = root / "input"
            input_dir.mkdir()
            cert = input_dir / "local-ca.pem"
            cert.write_bytes(ca_cert.read_bytes())
            other_cert = root / "other-ca.pem"
            other_key = root / "other-ca.key"
            self.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1", "-keyout", str(other_key), "-out", str(other_cert), "-subj", "/CN=unrelated-maintenance-ca"], timeout=60)
            untrusted_cert = input_dir / "untrusted-ca.pem"
            untrusted_cert.write_bytes(other_cert.read_bytes())
            package = "maintenanceprobe" + uuid.uuid4().hex
            wheel = input_dir / f"{package}-1.0.0-py3-none-any.whl"
            with zipfile.ZipFile(wheel, "w") as archive:
                archive.writestr(f"{package}-1.0.0.dist-info/METADATA", f"Metadata-Version: 2.1\nName: {package}\nVersion: 1.0.0\n")
                archive.writestr(f"{package}-1.0.0.dist-info/WHEEL", "Wheel-Version: 1.0\nGenerator: trusted-validator\nRoot-Is-Purelib: true\nTag: py3-none-any\n")
                archive.writestr(f"{package}-1.0.0.dist-info/RECORD", "")
            class Handler(http.server.BaseHTTPRequestHandler):
                def do_GET(self):
                    if self.path == f"/simple/{package}/":
                        body = f'<a href="/packages/{wheel.name}">{package}</a>'.encode()
                    elif self.path == f"/packages/{wheel.name}":
                        body = wheel.read_bytes()
                    else:
                        self.send_error(404)
                        return
                    self.send_response(200)
                    self.send_header("Content-Type", "text/html" if self.path.startswith("/simple/") else "application/octet-stream")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                def log_message(self, _format, *_args):
                    return
            server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.load_cert_chain(server_cert, server_key)
            server.socket = context.wrap_socket(server.socket, server_side=True)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                url = f"https://127.0.0.1:{server.server_port}/simple"
                args = [str(uv), "pip", "install", "--dry-run", "--no-deps", "--no-cache", "--break-system-packages", "--python", str(python), "--index-url", url, f"{package}==1.0.0"]
                prefix, trusted_ca, untrusted_ca, sandbox_env = self._uv_sandbox(input_dir, root / "scratch")
                if self.system.endswith("linux"):
                    self.run([*prefix, "--setenv", "SSL_CERT_FILE", trusted_ca, "--", *args], cwd=self.trusted, timeout=180)
                    self.run([*prefix, "--setenv", "SSL_CERT_FILE", untrusted_ca, "--", *args], cwd=self.trusted, timeout=180, check=False)
                else:
                    self.run([*prefix, *args], cwd=root / "scratch", timeout=180, env_overrides={**sandbox_env, "SSL_CERT_FILE": trusted_ca})
                    self.run([*prefix, *args], cwd=root / "scratch", timeout=180, env_overrides={**sandbox_env, "SSL_CERT_FILE": untrusted_ca}, check=False)
                negative_log = (self.output.with_name(self.output.name + ".logs") / f"{len(self.commands):03d}.log").read_text(encoding="utf-8", errors="replace").lower()
                if self.commands[-1]["exit_code"] == 0 or not any(marker in negative_log for marker in ("certificate verify", "unknown ca", "unknownissuer", "unknown issuer", "self-signed", "certificate error", "local issuer", "invalid peer certificate")):
                    raise ValidationError("candidate uv did not demonstrate rejection of an untrusted local TLS certificate")
                self.commands[-1]["expected_exit_code"] = self.commands[-1]["exit_code"]
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=5)

    def _uv_sandbox(self, probe_inputs: Path, scratch: Path) -> tuple[list[str], str, str, dict[str, str]]:
        scratch.mkdir(parents=True, exist_ok=True)
        probe_inputs = probe_inputs.resolve()
        scratch = scratch.resolve()
        if self.system.endswith("linux"):
            hosts = _json(self.trusted / POLICY_REL).get("native_hosts", {}).get(self.system, [])
            host = next((name for name in hosts if name in ("thorny", "tater")), hosts[0] if hosts else "")
            if not host:
                raise ValidationError("trusted policy has no representative Linux host for uv sandbox")
            bwrap_path = Path(self._build_path(f"nixosConfigurations.{host}.pkgs.bubblewrap", cwd=self.trusted)) / "bin/bwrap"
            prefix = [str(bwrap_path), "--unshare-user", "--unshare-pid", "--unshare-ipc", "--unshare-uts", "--unshare-cgroup", "--share-net", "--die-with-parent", "--new-session", "--ro-bind", "/nix/store", "/nix/store", "--proc", "/proc", "--dev", "/dev", "--tmpfs", "/tmp", "--dir", "/tmp/home", "--dir", "/tmp/cache", "--ro-bind", str(probe_inputs), "/probe", "--chdir", "/tmp", "--setenv", "HOME", "/tmp/home", "--setenv", "UV_CACHE_DIR", "/tmp/cache"]
            return prefix, "/probe/local-ca.pem", "/probe/untrusted-ca.pem", {}
        sandbox_exec = "/usr/bin/sandbox-exec"
        if not Path(sandbox_exec).is_file():
            raise ValidationError("Darwin sandbox-exec is required for the uv trust probe")
        profile = scratch / "uv-probe.sb"
        profile.write_text(
            "(version 1)\n(deny default)\n(allow process-exec)\n(allow process-fork)\n(allow process-info*)\n"
            "(allow signal (target same-sandbox))\n(allow sysctl-read)\n(allow file-read*)\n"
            "(deny file-read* (subpath \"/Users\"))\n(deny file-read* (subpath \"/System/Volumes/Data/Users\"))\n"
            "(deny file-read* (subpath \"/var/root\"))\n(deny file-read* (subpath \"/private/var/root\"))\n"
            "(deny file-read* (subpath \"/private/var/folders\"))\n(deny file-read* (subpath \"/etc/nix\"))\n"
            "(deny file-read* (subpath \"/private/etc/nix\"))\n(deny file-read* (subpath \"/etc/ssh\"))\n"
            "(deny file-read* (subpath \"/private/etc/ssh\"))\n(deny file-read* (subpath \"/Library/Keychains\"))\n"
            f"(allow file-read* (subpath \"{probe_inputs}\") (subpath \"{scratch}\"))\n"
            f"(allow file-write* (subpath \"{scratch}\"))\n"
            "(allow network-outbound (remote ip \"localhost:*\"))\n",
            encoding="utf-8",
        )
        return [sandbox_exec, "-f", str(profile)], str(probe_inputs / "local-ca.pem"), str(probe_inputs / "untrusted-ca.pem"), {"HOME": str(scratch), "TMPDIR": str(scratch), "UV_CACHE_DIR": str(scratch / "cache")}

    def _lint(self) -> None:
        if self.system == "x86_64-linux":
            script = self.trusted / "scripts/ci-check-tiers.sh"
            path = _safe_environment().get("PATH", "")
            real_nix = shutil.which("nix", path=path)
            if not real_nix:
                raise ValidationError("trusted nix executable must be available on PATH")
            real_nix = os.path.realpath(real_nix)
            with tempfile.TemporaryDirectory(prefix="dotfiles-nix-guard-") as guard_dir:
                guard = Path(guard_dir) / "nix"
                guard.write_text(
                    f"#!{sys.executable}\n"
                    "import os, sys\n"
                    f"real = {real_nix!r}\n"
                    "args = [arg for arg in sys.argv[1:] if arg != '--accept-flake-config']\n"
                    "if '--no-update-lock-file' not in args: args.append('--no-update-lock-file')\n"
                    "if '--no-write-lock-file' not in args: args.append('--no-write-lock-file')\n"
                    "if not any(args[i:i+2] == ['--option', 'sandbox'] for i in range(len(args))): args += ['--option', 'sandbox', 'true']\n"
                    "os.execv(real, [real, *args])\n",
                    encoding="utf-8",
                )
                guard.chmod(guard.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
                self.run(
                    [
                        real_nix, "develop", f"{self.trusted}#ci", "--no-update-lock-file",
                        "--no-write-lock-file", "--option", "sandbox", "true",
                        "--command", "bash", "-c",
                        'PATH="$1:$PATH"; export PATH; shift; exec bash "$@"',
                        "dotfiles-nix-guard", guard_dir, str(script), "fast",
                    ],
                    cwd=self.candidate,
                )

    def execute(self) -> dict[str, Any]:
        status = "failed"
        error: str | None = None
        try:
            policy, self.identity = self._check_identity()
            hosts = self._verify_native(policy)
            lock = _json(self.candidate / "flake.lock")
            self._compare_flake_warnings()
            self._lint()
            self._validate_flake(hosts)
            self._check_hold(policy, hosts, lock)
            status = "passed"
        except Exception as exc:  # Always produce a bounded failure shard.
            error = str(exc)[:1000]
            self.warnings.append(error)
        evidence = {
            "schema": 1,
            **self.identity,
            "system": self.system,
            "status": status,
            "created_at": int(time.time()),
            "commands": self.commands,
            "warnings": self.warnings[:MAX_WARNINGS],
            "warning_comparison": self.warning_comparison,
            "holds": self.holds,
        }
        if error:
            evidence["error"] = error
        self.output.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.output.with_name(self.output.name + ".tmp")
        temporary.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        temporary.replace(self.output)
        return evidence


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trusted", required=True, type=Path)
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--system", required=True)
    parser.add_argument("--identity", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args(argv)
    result = Validator(args.trusted, args.candidate, args.system, args.identity, args.output).execute()
    print(json.dumps({"status": result["status"], "output": str(args.output)}))
    return 0 if result["status"] == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())
