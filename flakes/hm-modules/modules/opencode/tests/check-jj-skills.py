#!/usr/bin/env python3
"""Check the four generic Jujutsu and Bay skills as one bounded suite."""
from pathlib import Path
import os, re, sys

ROOT = Path(os.environ["OPENCODE_SKILL_ROOT"]) if "OPENCODE_SKILL_ROOT" in os.environ else Path(__file__).resolve().parents[5]
HM = ROOT if (ROOT / "modules/opencode").is_dir() else ROOT / "flakes/hm-modules"
SKILLS = HM / "modules/opencode/skills"
REGISTRY = HM / "modules/opencode/skills.nix"
IDS = ("jj-change-management", "jj-conflict-resolution", "jj-repo-workflow", "bay-workspaces")
LIMITS = {"jj-change-management": 600, "jj-conflict-resolution": 325, "jj-repo-workflow": 600, "bay-workspaces": 750}
errors = []
texts = {}

def require(ok, message):
    if not ok: errors.append(message)

for skill_id in IDS:
    path = SKILLS / skill_id / "SKILL.md"
    require(path.is_file(), f"missing {path.relative_to(ROOT)}")
    if not path.is_file(): continue
    text = path.read_text()
    texts[skill_id] = text
    name = re.search(r"^name:\s*([^\s]+)$", text, re.M)
    desc = re.search(r"^description:\s*(.+)$", text, re.M)
    require(name and name.group(1).strip('"') == skill_id, f"{skill_id}: frontmatter name mismatch")
    require(desc is not None, f"{skill_id}: missing one-line description")
    if desc:
        require(len(re.findall(r"\b[\w'-]+\b", desc.group(1))) <= 55, f"{skill_id}: description exceeds 55 words")
    words = len(re.findall(r"\b[\w'-]+\b", text))
    require(words <= LIMITS[skill_id], f"{skill_id}: {words} words exceeds {LIMITS[skill_id]}")

require(sum(len(re.findall(r"\b[\w'-]+\b", t)) for t in texts.values()) <= 2000, "generic skill suite exceeds 2000 words")
require(not (SKILLS / "jj-workspaces").exists(), "legacy jj-workspaces directory exists")
registry = REGISTRY.read_text()
registered = set(re.findall(r"^\s{2}([\w-]+)\s*=", registry, re.M))
require(set(IDS) <= registered, "generic IDs missing from skills.nix")
generic_registered = {skill_id for skill_id in registered if skill_id.startswith("jj-") or skill_id == "bay-workspaces"}
require(generic_registered == set(IDS), f"generic registry IDs differ: {sorted(generic_registered)}")
require("jj-workspaces" not in registry, "legacy jj-workspaces registry entry exists")

all_repo_text = "\n".join(p.read_text(errors="ignore") for p in ROOT.rglob("*") if p.is_file() and p.name != "check-jj-skills.py" and ".jj" not in p.parts)
require("jj-workspaces" not in all_repo_text, "legacy jj-workspaces reference exists")

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
        require(target in registered, f"{source_id}: unregistered cross-reference {target}")

if errors:
    print("\n".join(f"error: {e}" for e in errors), file=sys.stderr)
    raise SystemExit(1)
for skill_id, text in texts.items():
    print(f"{skill_id}: {len(re.findall(r'\b[\w\'-]+\b', text))} words")
