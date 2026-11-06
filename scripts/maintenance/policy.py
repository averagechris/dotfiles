"""Deterministic eligibility checks, always loaded from the trusted base."""
from __future__ import annotations

import json
from pathlib import Path, PurePosixPath
import re
import subprocess

from maintenance.common import Blocked, require

SHARED_NODES = (
    "nixpkgs", "home-manager", "darwin", "opencode", "agenix", "deploy-rs",
    "nixos-hardware", "disko", "ctx", "fleet", "fleet-cli", "fleet-srht",
    "sideshow", "rdny", "hyprland", "Hyprspace", "hypridle", "anyrun",
    "pip-chrome-extension", "nitter-link", "t3-code-nix", "memo", "starship-jj",
    "linear-cli", "gander", "titlecase",
)
ASSIGNMENT = re.compile(r'\b(version|hash)\s*=\s*"([^"\n]*)"\s*;')


def safe_path(name):
    require(isinstance(name, str) and str(PurePosixPath(name)) == name and
            not name.startswith("/") and ".." not in PurePosixPath(name).parts and
            "\\" not in name and "\0" not in name, "invalid changed path")
    return name


def package_shape(text):
    def replace(match):
        kind, value = match.groups()
        if kind == "version":
            require(re.fullmatch(r"[0-9]+(?:\.[0-9]+)+(?:[a-zA-Z0-9.+-]*)", value), "invalid package version")
        else:
            require(re.fullmatch(r"sha256-[A-Za-z0-9+/]{43}=", value), "invalid package hash")
        return kind + ' = "<updated>";'
    return ASSIGNMENT.sub(replace, text)


def check_lock(before, after):
    require(before.get("version") == after.get("version") == 7, "unsupported lockfile format")
    require(before.get("root") == after.get("root") == "root", "changed lock root")
    old, new = before["nodes"], after["nodes"]
    require(old["root"] == new["root"], "root input topology changed")
    old_sources = {json.dumps(v.get("original"), sort_keys=True) for v in old.values() if "original" in v}
    for name, node in new.items():
        if name in old:
            require(node.get("original") == old[name].get("original"), "dependency role changed its source")
            require(("locked" in node) == ("locked" in old[name]), "dependency changed its locked role")
        if "original" not in node:
            continue
        require(json.dumps(node["original"], sort_keys=True) in old_sources, "new or changed dependency source requires owner review")
        original = node["original"]
        locked = node.get("locked", {})
        require(locked.get("type") in {"github", "git", "path", "tarball"}, "unsupported locked source")
        require(locked.get("type") == original.get("type"), "locked source type differs from original")
        identity_fields = {"github": ("owner", "repo"), "git": ("url",),
                           "tarball": ("url",), "path": ("path",)}
        require(all(locked.get(key) == original.get(key) for key in identity_fields[locked["type"]]),
                "locked source identity differs from original")
        if original.get("type") == "path":
            previous = [v for v in old.values() if v.get("original") == original]
            require(any(v.get("inputs") == node.get("inputs") and v.get("parent") == node.get("parent")
                        for v in previous), "local path input topology changed")
        if original.get("rev"):
            require(locked.get("rev") == original["rev"], "explicit revision pin changed")
        # Version tags remain pinned; release changes need an explicit URL change.
        if re.match(r"^v?\d+\.\d+", original.get("ref", "")):
            previous = [v for v in old.values() if v.get("original") == original]
            require(all(v.get("locked") == locked for v in previous), "version tag moved")


def check_contents(policy, changed, before, after):
    require(0 < len(changed) <= policy["max_changed_files"], "unexpected number of changed files")
    allowed = set(policy["canonical_locks"]) | set(policy["manual_packages"])
    require(set(changed) <= allowed, "candidate changes protected paths")
    total = 0
    for name in changed:
        safe_path(name)
        old, new = before(name), after(name)
        require(isinstance(old, bytes) and isinstance(new, bytes), "invalid file content")
        total += len(old) + len(new)
        if name.endswith("flake.lock"):
            check_lock(json.loads(old), json.loads(new))
        else:
            require(package_shape(old.decode()) == package_shape(new.decode()), "package code changed beyond version/hash updates")
    require(total <= 6_000_000, "candidate source exceeds size limit")
    root = json.loads(after("flake.lock"))["nodes"]
    revision = root["nixpkgs"]["locked"]["rev"]
    for name in policy["canonical_locks"]:
        nodes = json.loads(after(name))["nodes"]
        require(nodes["nixpkgs"]["locked"]["rev"] == revision, "canonical nixpkgs revisions differ")
        require(nodes["nixpkgs"]["original"].get("ref") == "nixos-unstable", "nixpkgs channel changed")
        for shared in SHARED_NODES:
            if shared in root and shared in nodes:
                require(nodes[shared].get("original") == root[shared].get("original") and
                        nodes[shared].get("locked") == root[shared].get("locked"),
                        f"shared {shared} revisions differ")
    require(root.get("t3-code-nix", {}).get("inputs", {}).get("nixpkgs") == ["nixpkgs"], "t3-code-nix stopped following nixpkgs")
    return {"nixpkgs": revision, "changed": sorted(changed)}


def local_check(policy, trusted, candidate):
    result = subprocess.run(["git", "diff", "--name-status", "HEAD"], cwd=candidate,
                            check=True, capture_output=True, text=True)
    names = []
    for line in result.stdout.splitlines():
        status, name = line.split("\t", 1)
        require(status == "M", "candidate adds, deletes, or renames files")
        require(not (Path(candidate) / name).is_symlink() and not (Path(trusted) / name).is_symlink(),
                "candidate contains a symlink")
        names.append(name)
    untracked = subprocess.run(["git", "ls-files", "--others", "--exclude-standard"], cwd=candidate,
                               check=True, capture_output=True, text=True)
    require(not untracked.stdout.strip(), "candidate has untracked files")
    return check_contents(policy, names, lambda p: (Path(trusted) / p).read_bytes(),
                          lambda p: (Path(candidate) / p).read_bytes())
