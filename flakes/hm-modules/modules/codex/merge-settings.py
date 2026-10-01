"""Merge declared settings without taking ownership of desktop configuration."""

import json
import os
from pathlib import Path
import sys
import tempfile

import tomlkit


def flatten(value, prefix=()):
    for key, item in value.items():
        path = (*prefix, key)
        if isinstance(item, dict):
            yield from flatten(item, path)
        else:
            yield path, item


def lookup(document, path):
    value = document
    for key in path:
        if not isinstance(value, dict) or key not in value:
            return False, None
        value = value[key]
    return True, value


def remove(document, path):
    parent = document
    ancestors = []
    for key in path[:-1]:
        ancestors.append((parent, key))
        parent = parent[key]
    del parent[path[-1]]
    for ancestor, key in reversed(ancestors):
        if ancestor[key]:
            break
        del ancestor[key]


def assign(document, path, value):
    parent = document
    for key in path[:-1]:
        if key not in parent:
            parent[key] = tomlkit.table()
        if not isinstance(parent[key], dict):
            raise ValueError(f"Cannot merge table through existing scalar: {'.'.join(path)}")
        parent = parent[key]
    parent[path[-1]] = value


def atomic_write(path, content):
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w") as output:
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def merge(directory, settings):
    config = directory / "config.toml"
    ownership = directory / "dotfiles-managed-settings.json"
    # Parse everything before modifying any file. Empty first-time settings
    # leave the app's configuration completely untouched.
    previous = json.loads(ownership.read_text()) if ownership.exists() else {}
    if not settings and not previous:
        return
    if config.is_symlink():
        raise ValueError("config.toml is a symlink; migrate from immutable config before merging")
    original = config.read_text() if config.exists() else ""
    document = tomlkit.parse(original)
    current_paths = dict(flatten(settings))
    for path, value in flatten(previous):
        if path not in current_paths:
            present, local_value = lookup(document, path)
            if present and local_value == value:
                remove(document, path)
    for path, value in current_paths.items():
        assign(document, path, value)
    rendered = tomlkit.dumps(document)
    directory.mkdir(parents=True, exist_ok=True)
    if rendered != original:
        # Preserve the original once for recovery. Later generations keep the
        # same backup instead of replacing it with already-managed settings.
        backup = directory / "config.toml.before-dotfiles"
        if config.exists() and not backup.exists():
            atomic_write(backup, original)
        atomic_write(config, rendered)
    atomic_write(ownership, json.dumps(settings, indent=2) + "\n")


if __name__ == "__main__":
    merge(Path(sys.argv[1]), json.loads(Path(sys.argv[2]).read_text()))
