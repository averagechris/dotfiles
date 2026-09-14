#!/usr/bin/env python3
"""Focused behavioral checks for OpenCode session cleanup."""

import datetime
import json
import pathlib
import re
import socket
import subprocess
import sys
import tempfile
import time
import os

MODULE = pathlib.Path(os.environ.get("SESSION_CLEANUP_MODULE", pathlib.Path(__file__).with_name("session-cleanup.nix")))
GUARD = pathlib.Path(os.environ.get("SESSION_CLEANUP_GUARD", MODULE.with_name("service-guard.sh")))
source = MODULE.read_text()
match = re.search(r"select_candidates\(\) \{\n\s+python3 - .*? <<'PY'\n(.*?)\n      PY", source, re.S)
assert match, "candidate selector heredoc not found"
selector = match.group(1).replace("      ", "", 1).replace("\n      ", "\n")


def select(rows, minimum=2):
    payloads = [{"data": rows[:2], "cursor": {"next": "fixture"}}, {"data": rows[2:], "cursor": {}}]
    with tempfile.NamedTemporaryFile("w", encoding="utf-8") as fixture:
        for payload in payloads:
            fixture.write(json.dumps(payload) + "\n")
        fixture.flush()
        result = subprocess.run(
            [sys.executable, "-c", selector, "45", str(minimum), fixture.name],
            text=True,
            capture_output=True,
            check=True,
        )
    return result.stdout.splitlines()


old = (datetime.datetime.now(datetime.UTC) - datetime.timedelta(days=60)).isoformat()
new = datetime.datetime.now(datetime.UTC).isoformat()
rows = [
    {"id": "old-root", "time": {"updated": old}},
    {"id": "old-child", "parentID": "old-root", "time": {"updated": old}},
    {"id": "mixed-root", "time": {"updated": old}},
    {"id": "new-child", "parentID": "mixed-root", "time": {"updated": new}},
    {"id": "new-root", "time": {"updated": new}},
]
assert select(rows) == ["old-root"], "must delete a wholly old tree but not cascade through protected/new children"


def guard_stub_contract():
    with tempfile.TemporaryDirectory(prefix="opencode-session-cleanup-guard-") as root:
        root = pathlib.Path(root)
        (root / "bin").mkdir()
        trace = root / "trace"
        stub = root / "bin" / "opencode"
        stub.write_text(
            """#!/bin/sh
printf '%s\\n' "$*" >> "$OPENCODE_GUARD_TRACE"
if [ "$*" = "service status" ]; then
    printf 'stopped\\n'
    exit 0
fi
exit 99
""",
            encoding="utf-8",
        )
        stub.chmod(0o755)
        stamp = root / "last-run"
        env = os.environ.copy()
        env.update(PATH=f"{root / 'bin'}:/usr/bin:/bin", OPENCODE_GUARD_TRACE=str(trace))
        harness = f'. "{GUARD}"\nrequire_running_opencode_service || exit 75\nprintf done > "{stamp}"\n'
        result = subprocess.run(["/bin/bash", "-c", harness], env=env, text=True, capture_output=True)
        assert result.returncode == 75, result
        assert trace.read_text(encoding="utf-8").splitlines() == ["service status"]
        assert not stamp.exists()


def no_server_guard_contract(binary):
    with tempfile.TemporaryDirectory(prefix="opencode-session-cleanup-cold-") as root:
        root = pathlib.Path(root)
        for name in ("home", "config", "data", "state", "bin"):
            (root / name).mkdir()
        (root / "bin" / "opencode").symlink_to(binary)
        stamp = root / "state" / "last-run"
        env = os.environ.copy()
        env.update(
            HOME=str(root / "home"),
            XDG_CONFIG_HOME=str(root / "config"),
            XDG_DATA_HOME=str(root / "data"),
            XDG_STATE_HOME=str(root / "state"),
            PATH=f"{root / 'bin'}:/usr/bin:/bin",
        )
        before = subprocess.run([binary, "service", "status"], env=env, text=True, capture_output=True, check=True)
        assert before.stdout.strip() == "stopped"
        harness = f'. "{GUARD}"\nrequire_running_opencode_service || exit 75\nprintf done > "{stamp}"\n'
        guarded = subprocess.run(["/bin/bash", "-c", harness], env=env, text=True, capture_output=True)
        assert guarded.returncode == 75, guarded
        assert not stamp.exists()
        after = subprocess.run([binary, "service", "status"], env=env, text=True, capture_output=True, check=True)
        assert after.stdout.strip() == "stopped"


def runtime_contract():
    guard_stub_contract()
    binary = os.environ.get("OPENCODE_V2_BIN")
    if not binary:
        print("runtime contract skipped (set OPENCODE_V2_BIN)")
        return
    no_server_guard_contract(binary)
    with tempfile.TemporaryDirectory(prefix="opencode-session-cleanup-") as root:
        root = pathlib.Path(root)
        for name in ("home", "config", "data", "state", "project-a", "project-b"):
            (root / name).mkdir()
        env = os.environ.copy()
        env.update(
            HOME=str(root / "home"),
            XDG_CONFIG_HOME=str(root / "config"),
            XDG_DATA_HOME=str(root / "data"),
            XDG_STATE_HOME=str(root / "state"),
            OPENCODE_CONFIG_DIR=str(root / "config" / "opencode"),
            OPENCODE_DISABLE_CHANNEL_DB="1",
            OPENCODE_SERVER_PASSWORD="session-cleanup-test",
        )
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        server_url = f"http://127.0.0.1:{port}"
        log_path = root / "server.log"
        with log_path.open("w", encoding="utf-8") as log:
            server = subprocess.Popen(
                [binary, "serve", "--hostname", "127.0.0.1", "--port", str(port), "--print-logs"],
                env=env,
                stdout=log,
                stderr=subprocess.STDOUT,
                text=True,
            )
            try:
                def api(operation, *, data=None, params=()):
                    command = [binary, "api", "--server", server_url, operation]
                    for param in params:
                        command += ["--param", param]
                    if data is not None:
                        command += ["--data", json.dumps(data)]
                    return json.loads(subprocess.run(command, env=env, text=True, capture_output=True, check=True).stdout)

                for _ in range(100):
                    try:
                        assert api("session.active")["data"] == {}
                        break
                    except (subprocess.CalledProcessError, AssertionError, json.JSONDecodeError):
                        time.sleep(0.05)
                else:
                    raise AssertionError("isolated V2 server did not become ready")

                def create(title, directory):
                    body = {"title": title, "location": {"directory": str(directory)}}
                    return api("session.create", data=body)["data"]

                old_root = create("old-root", root / "project-a")
                old_child = create("old-child", root / "project-a")
                mixed_root = create("mixed-root", root / "project-a")
                new_child = create("new-child", root / "project-a")
                new_root = create("new-root", root / "project-b")

                db = next((root / "data").rglob("opencode.db"))
                old_ms = int((time.time() - 60 * 86400) * 1000)
                updates = "\n".join(
                    f"UPDATE session_v2 SET time_updated = {old_ms} WHERE id = '{row['id']}';"
                    for row in (old_root, old_child, mixed_root)
                )
                subprocess.run(["/usr/bin/sqlite3", str(db)], input=updates, text=True, check=True)

                pages, cursor = [], None
                while True:
                    params = ["limit=1", "order=desc"] + ([f"cursor={cursor}"] if cursor else [])
                    page = api("session.list", params=params)
                    pages.append(page)
                    if not page["data"]:
                        break
                    cursor = page.get("cursor", {}).get("next")
                    if not cursor:
                        break
                listed = [row for page in pages for row in page["data"]]
                assert {row["id"] for row in listed} == {old_root["id"], old_child["id"], mixed_root["id"], new_child["id"], new_root["id"]}
                assert {row["location"]["directory"] for row in listed} == {str(root / "project-a"), str(root / "project-b")}
                assert all("updated" in row["time"] for row in listed)

                with tempfile.NamedTemporaryFile("w", encoding="utf-8") as fixture:
                    for page in pages:
                        fixture.write(json.dumps(page) + "\n")
                    fixture.flush()
                    chosen = subprocess.run(
                        [sys.executable, "-c", selector, "45", "2", fixture.name],
                        text=True, capture_output=True, check=True,
                    ).stdout.splitlines()
                assert set(chosen) == {old_root["id"], old_child["id"], mixed_root["id"]}
                for session_id in chosen:
                    subprocess.run([binary, "session", "delete", "--server", server_url, session_id], env=env, check=True, capture_output=True, text=True)
                remaining = api("session.list", params=["limit=100000", "order=desc"])["data"]
                assert {row["id"] for row in remaining} == {new_child["id"], new_root["id"]}
                print(f"runtime contract passed; server log: {log_path}")
            finally:
                server.terminate()
                try:
                    server.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    server.kill()
                    server.wait(timeout=5)


runtime_contract()
print("session cleanup tests passed")
