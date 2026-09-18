#!/usr/bin/env python3
"""Audit skill YAML and check the jj suite plus its host-specific cross-link."""
from pathlib import Path
import re, sys
import yaml

if len(sys.argv) not in (2, 3):
    raise SystemExit("usage: check-jj-skills.py SKILL_ROOT [SUREMAC_CONFIG]")

ROOT = Path(sys.argv[1])
HM = ROOT if (ROOT / "modules/opencode").is_dir() else ROOT / "flakes/hm-modules"
SKILLS = ROOT / "skills" if (ROOT / "skills").is_dir() else HM / "modules/opencode/skills"
REGISTRY = HM / "modules/opencode/skills.nix"
SUREMAC_CONFIG = Path(sys.argv[2]) if len(sys.argv) == 3 else None
IDS = ("jj-change-management", "jj-conflict-resolution", "jj-repo-workflow", "bay-workspaces")
LIMITS = {"jj-change-management": 600, "jj-conflict-resolution": 325, "jj-repo-workflow": 600, "bay-workspaces": 750}
HOST_SKILL = "suremac-jj-pr"
HOST_LIMIT = 1200
errors = []
texts = {}

def require(ok, message):
    if not ok: errors.append(message)

def frontmatter(path):
    text = path.read_text()
    match = re.match(r"\A---\s*\n(.*?)\n---\s*(?:\n|\Z)", text, re.S)
    require(match is not None, f"{path.parent.name}: missing YAML frontmatter")
    if not match:
        return None
    try:
        data = yaml.safe_load(match.group(1))
    except yaml.YAMLError as error:
        require(False, f"{path.parent.name}: invalid YAML frontmatter: {error}")
        return None
    require(isinstance(data, dict), f"{path.parent.name}: frontmatter must be a mapping")
    if not isinstance(data, dict):
        return None
    name, description = data.get("name"), data.get("description")
    require(isinstance(name, str) and bool(name.strip()), f"{path.parent.name}: name must be nonempty")
    require(isinstance(description, str) and bool(description.strip()), f"{path.parent.name}: description must be nonempty")
    require(name == path.parent.name, f"{path.parent.name}: frontmatter name mismatch")
    return data

for path in sorted(SKILLS.glob("*/SKILL.md")):
    frontmatter(path)

# The one-argument mode is used by the malformed-YAML negative fixture.
if SUREMAC_CONFIG is None:
    if errors:
        print("\n".join(f"error: {e}" for e in errors), file=sys.stderr)
        raise SystemExit(1)
    raise SystemExit(0)

for skill_id in IDS:
    path = SKILLS / skill_id / "SKILL.md"
    require(path.is_file(), f"missing {path.relative_to(ROOT)}")
    if not path.is_file(): continue
    text = path.read_text()
    texts[skill_id] = text
    metadata = frontmatter(path)
    if metadata and isinstance(metadata.get("description"), str):
        require(len(re.findall(r"\b[\w'-]+\b", metadata["description"])) <= 55, f"{skill_id}: description exceeds 55 words")
    words = len(re.findall(r"\b[\w'-]+\b", text))
    require(words <= LIMITS[skill_id], f"{skill_id}: {words} words exceeds {LIMITS[skill_id]}")

require(sum(len(re.findall(r"\b[\w'-]+\b", t)) for t in texts.values()) <= 2000, "generic skill suite exceeds 2000 words")
require(not (SKILLS / "jj-workspaces").exists(), "legacy jj-workspaces directory exists")
registry = REGISTRY.read_text()
registered = set(re.findall(r"^\s{2}([\w-]+)\s*=", registry, re.M))
require(set(IDS) <= registered, "generic IDs missing from skills.nix")
generic_registered = {skill_id for skill_id in registered if skill_id.startswith("jj-") or skill_id == "bay-workspaces"}
require(generic_registered == set(IDS), f"generic registry IDs differ: {sorted(generic_registered)}")
require(HOST_SKILL not in registered, f"{HOST_SKILL}: host-specific skill must not be globally registered")
require("jj-workspaces" not in registry, "legacy jj-workspaces registry entry exists")
require(SUREMAC_CONFIG.is_file(), f"{HOST_SKILL}: missing suremac config input {SUREMAC_CONFIG}")
if SUREMAC_CONFIG.is_file():
    registration = re.search(
        r"programs\.opencode\.skills\.suremac-jj-pr\s*=\s*builtins\.readFile\s+([^;]+);",
        SUREMAC_CONFIG.read_text(),
    )
    require(registration is not None, f"{HOST_SKILL}: missing suremac host registration")
    if registration:
        require("suremac-jj-pr/SKILL.md" in registration.group(1), f"{HOST_SKILL}: host registration points elsewhere")

host_path = SKILLS / HOST_SKILL / "SKILL.md"
require(host_path.is_file(), f"missing host-specific skill {host_path.relative_to(ROOT)}")
if host_path.is_file():
    host_text = host_path.read_text()
    host_words = len(re.findall(r"\b[\w'-]+\b", host_text))
    require(host_words <= HOST_LIMIT, f"{HOST_SKILL}: {host_words} words exceeds {HOST_LIMIT}")
    require("Use this skill only on `suremac`" in host_text, f"{HOST_SKILL}: missing host scope")

for skill_id, text in texts.items():
    commands = "\n".join(re.findall(r"```bash\n(.*?)```", text, re.S))
    require(not re.search(r"(^|\s)git(?:\s|$)", commands), f"{skill_id}: git command is forbidden")
    require("jj ws" not in commands, f"{skill_id}: jj ws command is forbidden")
    if skill_id == "bay-workspaces":
        require("jj ws" in text and text.count("jj ws") == 1, "bay-workspaces: compatibility mention must appear once")
        flow = ["bay repo find <query> --json", "bay repo clone <owner>/<repo> --json", "bay add <repo>/<workspace> --json"]
        positions = [text.find(item) for item in flow]
        require(all(p >= 0 for p in positions) and positions == sorted(positions), "bay-workspaces: find-clone-add JSON flow missing or out of order")
        for marker in ("absolute", "--dry-run", "unpublished", "trash", "Never add purge implicitly", "no_group", "collision", "archived", "OpenCode"):
            require(marker in text, f"bay-workspaces: missing safety marker {marker!r}")
        require(not re.search(r"^jj\s", commands, re.M), "bay-workspaces: only Bay command family is allowed")
    else:
        require(not re.search(r"^bay\s", commands, re.M), f"{skill_id}: Bay command belongs in bay-workspaces")

for source_id, text in texts.items():
    for target in re.findall(r"`((?:jj|bay|suremac)-[a-z-]+|conventional-commits)`", text):
        require(target in registered or target == HOST_SKILL, f"{source_id}: unknown cross-reference {target}")

if errors:
    print("\n".join(f"error: {e}" for e in errors), file=sys.stderr)
    raise SystemExit(1)
for skill_id, text in texts.items():
    print(f"{skill_id}: {len(re.findall(r'\b[\w\'-]+\b', text))} words")
if host_path.is_file():
    print(f"{HOST_SKILL}: {len(re.findall(r'\b[\w\'-]+\b', host_path.read_text()))} words (host-specific)")
