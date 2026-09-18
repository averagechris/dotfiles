#!/usr/bin/env python3
"""Validate evaluated Home Manager skill destinations with real YAML."""
import json, re, sys
from pathlib import Path
import yaml

if len(sys.argv) != 2:
    raise SystemExit("usage: check-deployed-skills.py MANIFEST")

errors = []
entries = json.loads(Path(sys.argv[1]).read_text())
for entry in entries:
    destination = Path(entry["destination"])
    source = Path(entry["source"])
    skill_id = destination.parent.name if destination.name == "SKILL.md" else destination.name
    skill = source / "SKILL.md" if source.is_dir() else source
    if not skill.is_file():
        errors.append(f"{skill_id}: deployed source has no SKILL.md: {source}")
        continue
    text = skill.read_text()
    match = re.match(r"\A---\s*\n(.*?)\n---\s*(?:\n|\Z)", text, re.S)
    if not match:
        errors.append(f"{skill_id}: missing YAML frontmatter")
        continue
    try:
        data = yaml.safe_load(match.group(1))
    except yaml.YAMLError as error:
        errors.append(f"{skill_id}: invalid YAML frontmatter: {error}")
        continue
    if not isinstance(data, dict):
        errors.append(f"{skill_id}: frontmatter must be a mapping")
        continue
    for field in ("name", "description"):
        if not isinstance(data.get(field), str) or not data[field].strip():
            errors.append(f"{skill_id}: {field} must be nonempty")
    if data.get("name") != skill_id:
        errors.append(f"{skill_id}: deployed destination/name mismatch ({data.get('name')!r})")

if errors:
    print("\n".join(f"error: {error}" for error in errors), file=sys.stderr)
    raise SystemExit(1)
print(f"audited {len(entries)} deployed skills")
