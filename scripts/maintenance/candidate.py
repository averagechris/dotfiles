"""Generate a bounded update candidate using only the trusted updater."""
from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from typing import Callable

from maintenance.common import Blocked, atomic_json, digest, load_policy, require, sha
from maintenance.policy import SHARED_NODES, local_check, safe_path

UPDATE_TIMEOUT = 4 * 60 * 60
INPUT_NAME = re.compile(r"^[A-Za-z0-9._-]+$")
MANUAL_PACKAGES = ("pi-coding-agent", "helium-bin")


class Candidate:
    def __init__(self, trusted: Path, candidate: Path, output: Path, *,
                 run: Callable[..., subprocess.CompletedProcess] = subprocess.run,
                 timeout: int = UPDATE_TIMEOUT):
        self.trusted = trusted.resolve()
        self.candidate = candidate.resolve()
        self.output = output.parent.resolve() / output.name
        self.run_command = run
        self.timeout = timeout

    def _git(self, root: Path, *args: str) -> str:
        result = self.run_command(["git", "-C", str(root), *args], check=True,
                                  capture_output=True, text=True, timeout=30)
        return result.stdout.strip()

    def _lock_paths(self, policy: dict) -> list[tuple[str, Path]]:
        result = []
        for rel in policy["canonical_locks"]:
            safe_path(rel)
            path = self.candidate / rel
            require(path.is_file() and not path.is_symlink(), f"missing regular canonical lock: {rel}")
            result.append((rel, path))
        return result

    def _sync_shared_nodes(self, policy: dict) -> None:
        locks = self._lock_paths(policy)
        root_data = json.loads((self.candidate / "flake.lock").read_bytes())
        root_nodes = root_data["nodes"]
        for rel, path in locks:
            if rel == "flake.lock":
                continue
            data = json.loads(path.read_bytes())
            nodes = data["nodes"]
            for name in SHARED_NODES:
                if name not in root_nodes or name not in nodes:
                    continue
                if nodes[name].get("original") == root_nodes[name].get("original"):
                    nodes[name]["locked"] = root_nodes[name]["locked"]
            path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")

    def _path_parents(self, policy: dict) -> None:
        """Refresh direct canonical path inputs in leaves-to-root order, offline."""
        entries = self._lock_paths(policy)
        canonical_dirs = {self.candidate / Path(name).parent for name, _ in entries}
        ordered = sorted(entries, key=lambda item: (-len(Path(item[0]).parts), item[0]))
        for rel, lock_path in ordered:
            flake_dir = self.candidate / Path(rel).parent
            data = json.loads(lock_path.read_bytes())
            root_inputs = data["nodes"][data["root"]].get("inputs", {})
            names = []
            for name, node_ref in root_inputs.items():
                if not INPUT_NAME.fullmatch(name):
                    raise Blocked("unsafe path input name")
                if isinstance(node_ref, list):
                    node_ref = node_ref[0] if node_ref else None
                node = data["nodes"].get(node_ref, {})
                original = node.get("original", {})
                if original.get("type") != "path" or not isinstance(original.get("path"), str):
                    continue
                target = (flake_dir / original["path"]).resolve()
                if target in canonical_dirs:
                    names.append(name)
            for name in sorted(names):
                with tempfile.NamedTemporaryFile(prefix="maintenance-lock-", suffix=".json", delete=False) as temp:
                    output_lock = Path(temp.name)
                try:
                    flake_ref = f"path:{self.candidate}?dir={Path(rel).parent.as_posix()}"
                    self._run(["nix", "flake", "update", name, "--offline", "--option", "sandbox", "true",
                               "--no-accept-flake-config", "--flake", flake_ref,
                               "--output-lock-file", str(output_lock)], cwd=self.candidate)
                    require(output_lock.is_file(), "offline path update produced no lock")
                    lock_path.write_bytes(output_lock.read_bytes())
                finally:
                    output_lock.unlink(missing_ok=True)

    def _run(self, argv: list[str], *, cwd: Path) -> None:
        env = dict(os.environ)
        env.pop("NIX_CONFIG", None)
        env.pop("NIX_PATH", None)
        env["DOTFILES_REPO_ROOT"] = str(self.candidate)
        result = self.run_command(argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                  text=True, timeout=self.timeout, check=False)
        require(result.returncode == 0, f"trusted updater command failed ({result.returncode})")

    def generate(self, policy: dict | None = None) -> dict:
        require(self.output != self.candidate and self.candidate not in self.output.parents,
                "artifact output must be outside candidate checkout")
        policy = policy or load_policy(self.trusted)[0]
        base = sha(self._git(self.trusted, "rev-parse", "HEAD"))
        require(self._git(self.candidate, "rev-parse", "HEAD") == base,
                "trusted and candidate checkouts must share base HEAD")

        argv = ["nix", "run", "--option", "sandbox", "true", "--no-accept-flake-config",
                f"{self.trusted}#update-flakes", "--", "--show-output"]
        for package in MANUAL_PACKAGES:
            argv.extend(["--manual-package", package])
        self._run(argv, cwd=self.candidate)
        self._sync_shared_nodes(policy)
        self._path_parents(policy)

        changed = self._git(self.candidate, "diff", "--name-only", "HEAD").splitlines()
        if not changed:
            require(not self._git(self.candidate, "status", "--porcelain=v1", "--untracked-files=all"),
                    "candidate checkout is not clean")
            return {"schema": 1, "base": base, "noop": True, "files": []}
        local_check(policy, self.trusted, self.candidate)
        files = []
        for name in sorted(changed):
            safe_path(name)
            before_path = self.trusted / name
            after_path = self.candidate / name
            require(before_path.is_file() and after_path.is_file() and
                    not before_path.is_symlink() and not after_path.is_symlink(),
                    "candidate changes a non-regular file")
            before = before_path.read_bytes()
            content = after_path.read_bytes()
            files.append({"path": name, "before_sha256": digest(before),
                          "content_base64": base64.b64encode(content).decode("ascii")})
        return {"schema": 1, "base": base, "noop": False, "files": files}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    generate = sub.add_parser("generate")
    generate.add_argument("--trusted", required=True, type=Path)
    generate.add_argument("--candidate", required=True, type=Path)
    generate.add_argument("--output", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        policy, _ = load_policy(args.trusted)
        candidate_root = args.candidate.resolve()
        output = args.output.parent.resolve() / args.output.name
        require(output != candidate_root and candidate_root not in output.parents,
                "artifact output must be outside candidate checkout")
        output.unlink(missing_ok=True)
        result = Candidate(args.trusted, args.candidate, output).generate(policy)
        atomic_json(output, result)
    except (Blocked, OSError, json.JSONDecodeError, subprocess.TimeoutExpired,
            subprocess.CalledProcessError) as exc:
        parser.exit(1, f"candidate generation blocked: {exc}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
