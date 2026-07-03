import json
import os
import re
import stat
import sys
import tomllib

context_path, config_path = sys.argv[1:3]

with open(context_path, "r", encoding="utf-8") as handle:
    desired_context = json.load(handle)

data = {}
if os.path.exists(config_path):
    with open(config_path, "rb") as handle:
        data = tomllib.load(handle)

# Match the CLI's on-disk secret hygiene: auth tokens live in the OS
# keyring, not in the config file. Preserve workspace/profile metadata, but
# never re-emit legacy plaintext secrets if an old config still contains
# them. Blank token values instead of deleting the keys: the CLI's config
# parser requires `oauth.access_token` to be present.
data.pop("api_key", None)
for workspace in data.get("workspaces", {}).values():
    if isinstance(workspace, dict):
        workspace["api_key"] = ""
        oauth = workspace.get("oauth")
        if isinstance(oauth, dict):
            for token_key in ("access_token", "refresh_token"):
                if token_key in oauth:
                    oauth[token_key] = ""

data["context"] = desired_context

bare_key = re.compile(r"^[A-Za-z0-9_-]+$")


def quote_string(value):
    return json.dumps(value, ensure_ascii=False)


def key_segment(key):
    return key if bare_key.match(key) else quote_string(key)


def scalar(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return repr(float(value)) if isinstance(value, float) else str(value)
    if isinstance(value, str):
        return quote_string(value)
    raise TypeError(f"unsupported TOML scalar: {value!r}")


def inline_table(mapping):
    parts = []
    for key in sorted(mapping):
        value = mapping[key]
        if isinstance(value, dict):
            rendered = inline_table(value)
        elif isinstance(value, list):
            rendered = array(value)
        elif value is None:
            continue
        else:
            rendered = scalar(value)
        parts.append(f"{key_segment(key)} = {rendered}")
    return "{ " + ", ".join(parts) + " }"


def array(values):
    if all(not isinstance(value, dict) for value in values):
        return "[" + ", ".join(scalar(value) for value in values) + "]"
    return "[" + ", ".join(inline_table(value) for value in values) + "]"


def emit_table(lines, prefix, mapping):
    scalar_items = []
    child_tables = []
    array_tables = []

    for key in sorted(mapping):
        value = mapping[key]
        if value is None:
            continue
        if isinstance(value, dict):
            child_tables.append((key, value))
        elif isinstance(value, list) and any(isinstance(item, dict) for item in value):
            array_tables.append((key, value))
        else:
            scalar_items.append((key, value))

    if prefix:
        lines.append(f"[{'.'.join(key_segment(part) for part in prefix)}]")
    for key, value in scalar_items:
        lines.append(f"{key_segment(key)} = {array(value) if isinstance(value, list) else scalar(value)}")
    if scalar_items and (child_tables or array_tables):
        lines.append("")

    for index, (key, value) in enumerate(child_tables):
        emit_table(lines, prefix + [key], value)
        if index != len(child_tables) - 1 or array_tables:
            lines.append("")

    for table_index, (key, values) in enumerate(array_tables):
        for value_index, value in enumerate(values):
            lines.append(f"[[{'.'.join(key_segment(part) for part in prefix + [key])}]]")
            emit_table(lines, [], value)
            if value_index != len(values) - 1:
                lines.append("")
        if table_index != len(array_tables) - 1:
            lines.append("")


lines = []
top_scalars = {key: value for key, value in data.items() if key != "context" and not isinstance(value, dict) and value is not None}
for key in sorted(top_scalars):
    lines.append(f"{key_segment(key)} = {array(top_scalars[key]) if isinstance(top_scalars[key], list) else scalar(top_scalars[key])}")
if top_scalars:
    lines.append("")

for key in sorted(key for key in data if key != "context" and isinstance(data[key], dict)):
    emit_table(lines, [key], data[key])
    lines.append("")

emit_table(lines, ["context"], data["context"])
content = "\n".join(lines).rstrip() + "\n"

os.makedirs(os.path.dirname(config_path), exist_ok=True)
tmp_path = os.path.join(os.path.dirname(config_path), ".config.toml.tmp")
with open(tmp_path, "w", encoding="utf-8") as handle:
    handle.write(content)
os.chmod(tmp_path, stat.S_IRUSR | stat.S_IWUSR)
os.replace(tmp_path, config_path)
