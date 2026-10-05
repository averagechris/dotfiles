#!/usr/bin/env python3
"""Read Codex session summaries from Michi's private app-server socket."""

from __future__ import annotations

import argparse
import heapq
import json
import os
import re
import socket
import stat
import sys
import time
from pathlib import Path
from typing import Any


DEFAULT_ROOT = Path("/var/lib/zeroclaw-home/agents/owner/workspace")
REMOTE_RUNTIME_DIR = Path("/run/michi-codex-remote")
RPC_TIMEOUT_SECONDS = 15
MAX_OUTPUT_CHARS = 12_000
MAX_JOB_DIRS = 100
MAX_JOB_STATE_BYTES = 16_384
MAX_EVENTS_PREFIX_BYTES = 4096
SESSION_ID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)
JOB_ID_RE = re.compile(r"^[0-9a-f]{32}$")
SOCKET_TARGET_RE = re.compile(r"^/tmp/codex-daemon-([0-9]+)/([0-9a-f]{64})$")
MODEL_NAMES = {"luna": "gpt-6-luna", "sol": "gpt-6.1-sol", "astra": "gpt-6-astra"}


class SessionError(Exception):
    pass


def configured_root() -> Path:
    value = os.environ.get("MICHI_CODEX_ROOT")
    try:
        root = Path(value) if value else DEFAULT_ROOT
        root = root.resolve(strict=True)
    except OSError as exc:
        raise SessionError("owner workspace is unavailable") from exc
    if not root.is_dir():
        raise SessionError("owner workspace is unavailable")
    return root


def app_server_socket(root: Path) -> Path:
    alias = root / ".codex" / "michi-app-server.sock"
    try:
        alias_info = alias.lstat()
        if not stat.S_ISLNK(alias_info.st_mode) or alias_info.st_uid != os.geteuid():
            raise SessionError("Codex app-server socket alias is unsafe")
        target = os.readlink(alias)
    except FileNotFoundError as exc:
        raise SessionError("Codex app-server socket is unavailable; the phone host may be stopped") from exc
    except OSError as exc:
        raise SessionError("cannot inspect the Codex app-server socket alias") from exc

    match = SOCKET_TARGET_RE.fullmatch(target)
    if not match or int(match.group(1)) != os.geteuid():
        raise SessionError("Codex app-server socket alias has an invalid target")

    runtime = REMOTE_RUNTIME_DIR
    try:
        runtime_info = runtime.lstat()
        if (
            not stat.S_ISDIR(runtime_info.st_mode)
            or stat.S_ISLNK(runtime_info.st_mode)
            or runtime_info.st_uid != os.geteuid()
            or stat.S_IMODE(runtime_info.st_mode) & 0o077
        ):
            raise SessionError("Codex remote runtime directory is unsafe")
        path = runtime / f"codex-daemon-{match.group(1)}" / match.group(2)
        parent_info = path.parent.lstat()
        socket_info = path.lstat()
    except FileNotFoundError as exc:
        raise SessionError("Codex app-server socket is unavailable; the phone host may be stopped") from exc
    except OSError as exc:
        raise SessionError("cannot inspect the Codex app-server socket") from exc
    if (
        not stat.S_ISDIR(parent_info.st_mode)
        or stat.S_ISLNK(parent_info.st_mode)
        or parent_info.st_uid != os.geteuid()
        or not stat.S_ISSOCK(socket_info.st_mode)
        or socket_info.st_uid != os.geteuid()
    ):
        raise SessionError("Codex app-server socket is unsafe")
    if len(os.fsencode(path)) >= 108:
        raise SessionError("Codex app-server socket path exceeds the Unix socket limit")
    return path


def event_session_id(path: Path) -> str | None:
    try:
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
        with os.fdopen(fd, "rb") as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid():
                return None
            prefix = stream.read(MAX_EVENTS_PREFIX_BYTES)
    except OSError:
        return None
    for line in prefix.splitlines():
        try:
            event = json.loads(line)
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        if isinstance(event, dict) and event.get("type") == "thread.started":
            value = event.get("thread_id") or event.get("session_id")
            if isinstance(value, str) and SESSION_ID_RE.fullmatch(value):
                return value
    return None


def recent_job_rows(root: Path, session_statuses: dict[str, Any] | None = None) -> list[dict[str, Any]]:
    jobs_root = root / ".codex-jobs" / "jobs"
    try:
        jobs_info = jobs_root.lstat()
    except OSError:
        return []
    if (
        not stat.S_ISDIR(jobs_info.st_mode)
        or stat.S_ISLNK(jobs_info.st_mode)
        or jobs_info.st_uid != os.geteuid()
    ):
        return []

    newest: list[tuple[int, str, Path]] = []
    try:
        with os.scandir(jobs_root) as entries:
            for entry in entries:
                if not JOB_ID_RE.fullmatch(entry.name):
                    continue
                try:
                    info = entry.stat(follow_symlinks=False)
                except OSError:
                    continue
                if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid():
                    continue
                candidate = (info.st_mtime_ns, entry.name, Path(entry.path))
                if len(newest) < MAX_JOB_DIRS:
                    heapq.heappush(newest, candidate)
                elif candidate > newest[0]:
                    heapq.heapreplace(newest, candidate)
    except OSError:
        return []

    rows: list[dict[str, Any]] = []
    for _, job_id, directory in sorted(newest, reverse=True):
        state_path = directory / "state.json"
        try:
            fd = os.open(state_path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
            with os.fdopen(fd, "rb") as stream:
                info = os.fstat(stream.fileno())
                if (
                    not stat.S_ISREG(info.st_mode)
                    or info.st_uid != os.geteuid()
                    or info.st_size > MAX_JOB_STATE_BYTES
                ):
                    continue
                state = json.loads(stream.read(MAX_JOB_STATE_BYTES + 1))
        except (OSError, json.JSONDecodeError, UnicodeDecodeError):
            continue
        if not isinstance(state, dict) or state.get("id") != job_id:
            continue
        status = state.get("status")
        if not isinstance(status, str):
            continue
        session_id = state.get("session_id")
        if not isinstance(session_id, str) or not SESSION_ID_RE.fullmatch(session_id):
            session_id = None
        if session_id is None and status == "running":
            session_id = event_session_id(directory / "events.jsonl")

        row: dict[str, Any] = {
            "jobId": job_id,
            "jobStatus": status[:40],
        }
        model = state.get("model_name")
        if not isinstance(model, str):
            model = MODEL_NAMES.get(state.get("model"))
        if model:
            row["modelName"] = model[:80]
        reasoning = state.get("reasoning")
        if isinstance(reasoning, str):
            row["reasoning"] = reasoning[:20]
        if session_id:
            row["sessionId"] = session_id
            if session_statuses and session_id in session_statuses:
                row["codexSessionStatus"] = session_statuses[session_id]
        rows.append(row)
    return rows


def validate_session_id(value: str) -> str:
    if not SESSION_ID_RE.fullmatch(value):
        raise SessionError("session ID must be a lowercase Codex UUID")
    return value


class AppServerClient:
    def __init__(self, root: Path, websocket_module: Any | None = None):
        self.root = root
        self.websocket_module = websocket_module
        self.websocket: Any | None = None
        self.next_id = 1
        self.deadline = time.monotonic() + RPC_TIMEOUT_SECONDS

    def connect(self) -> None:
        socket_path = app_server_socket(self.root)
        try:
            if self.websocket_module is None:
                import websocket as websocket_module

                self.websocket_module = websocket_module
            else:
                websocket_module = self.websocket_module
        except ImportError as exc:
            raise SessionError("websocket-client is unavailable") from exc

        unix_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            unix_socket.settimeout(self._remaining())
            unix_socket.connect(str(socket_path))
            self.websocket = websocket_module.create_connection(
                "ws://localhost/",
                socket=unix_socket,
                timeout=self._remaining(),
            )
        except (OSError, TimeoutError, websocket_module.WebSocketException) as exc:
            unix_socket.close()
            raise SessionError("Codex session host is unavailable or timed out") from exc

        initialized = self.request(
            "initialize",
            {
                "clientInfo": {
                    "name": "michi-codex-sessions",
                    "title": "Michi Codex session reader",
                    "version": "1.0.0",
                },
                "capabilities": {"experimentalApi": True},
            },
        )
        if not isinstance(initialized, dict):
            raise SessionError("Codex app-server returned an invalid initialize response")
        self.notify("initialized", {})

    def _remaining(self) -> float:
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise SessionError("Codex session query timed out")
        return remaining

    def notify(self, method: str, params: dict[str, Any]) -> None:
        assert self.websocket is not None
        self.websocket.send(json.dumps({"jsonrpc": "2.0", "method": method, "params": params}))

    def request(self, method: str, params: dict[str, Any]) -> Any:
        assert self.websocket is not None
        request_id = self.next_id
        self.next_id += 1
        self.websocket.send(
            json.dumps({"jsonrpc": "2.0", "id": request_id, "method": method, "params": params})
        )
        while True:
            remaining = self._remaining()
            self.websocket.settimeout(remaining)
            try:
                message = self.websocket.recv()
            except (TimeoutError, OSError, self.websocket_module.WebSocketException) as exc:
                raise SessionError("Codex session query timed out or the host disconnected") from exc
            try:
                response = json.loads(message)
            except (TypeError, json.JSONDecodeError) as exc:
                raise SessionError("Codex app-server returned an invalid protocol message") from exc
            if not isinstance(response, dict) or response.get("id") != request_id:
                # App-server notifications can arrive between a request and its response.
                continue
            error = response.get("error")
            if isinstance(error, dict):
                code = error.get("code")
                raise SessionError(f"Codex app-server rejected the query (error {code})")
            if "result" not in response:
                raise SessionError("Codex app-server returned an incomplete response")
            return response["result"]

    def close(self) -> None:
        if self.websocket is not None:
            try:
                self.websocket.close()
            except Exception:
                pass
            self.websocket = None


def text_field(value: Any, limit: int) -> str | None:
    if not isinstance(value, str):
        return None
    if len(value) <= limit:
        return value
    return value[:limit] + "…"


def selected_fields(value: Any, fields: tuple[str, ...]) -> dict[str, Any]:
    if not isinstance(value, dict):
        return {}
    result: dict[str, Any] = {}
    for name in fields:
        if name not in value or value[name] is None:
            continue
        field = value[name]
        if name in {"name", "preview", "cwd", "model", "error"}:
            clipped = text_field(field, 500 if name == "preview" else 300)
            if clipped is not None:
                result[name] = clipped
        elif name == "status":
            status = selected_status(field)
            if status is not None:
                result[name] = status
        elif isinstance(field, (str, int, float, bool)):
            result[name] = field
    return result


def selected_status(value: Any) -> str | dict[str, Any] | None:
    if isinstance(value, str) and value in {
        "notLoaded", "idle", "systemError", "completed", "failed", "interrupted", "inProgress"
    }:
        return value
    if not isinstance(value, dict):
        return None
    # The app-server uses an internally tagged enum for thread status, e.g.
    # {"type":"idle"} or {"type":"active","activeFlags":[...]}. Keep
    # only the documented status tag and safe active flags.
    status_type = value.get("type")
    if status_type in {"notLoaded", "idle", "systemError"}:
        return status_type
    if status_type != "active":
        return None
    flags = value.get("activeFlags", [])
    if not isinstance(flags, list):
        return None
    accepted = {"waitingOnApproval", "waitingOnUserInput"}
    return {"type": "active", "activeFlags": [flag for flag in flags if flag in accepted]}


def selected_item(item: Any) -> dict[str, Any] | None:
    if not isinstance(item, dict):
        return None
    kind = item.get("type")
    if not isinstance(kind, str):
        return None
    result: dict[str, Any] = {"type": kind}
    if kind == "agentMessage":
        text = text_field(item.get("text"), 800)
        if text is not None:
            result["text"] = text
    elif kind == "userMessage":
        content = item.get("content")
        if isinstance(content, list):
            snippets = [
                text_field(part.get("text"), 300)
                for part in content
                if isinstance(part, dict) and part.get("type") == "text"
            ]
            text = "\n".join(value for value in snippets if value)[:500]
            if text:
                result["text"] = text
    elif kind == "commandExecution":
        command = text_field(item.get("command"), 300)
        if command:
            result["command"] = command
        status = item.get("status")
        if isinstance(status, str):
            result["status"] = status
    elif kind == "fileChange":
        changes = item.get("changes")
        if isinstance(changes, list):
            paths = [
                text_field(change.get("path"), 200)
                for change in changes[-8:]
                if isinstance(change, dict)
            ]
            result["paths"] = [path for path in paths if path]
    return result


def bounded_output(payload: dict[str, Any], collections: tuple[str, ...]) -> str:
    payload["truncated"] = False
    while True:
        rendered = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
        if len(rendered) <= MAX_OUTPUT_CHARS:
            return rendered
        trimmed = False
        for collection in collections:
            rows = payload.get(collection)
            if isinstance(rows, list) and rows:
                rows.pop()
                payload["truncated"] = True
                trimmed = True
                break
        if trimmed:
            continue
        minimal: dict[str, Any] = {collection: [] for collection in collections}
        minimal["truncated"] = True
        session = payload.get("session")
        if isinstance(session, dict) and session.get("id"):
            minimal["session"] = {"id": session["id"]}
        rendered = json.dumps(minimal, ensure_ascii=False, separators=(",", ":"))
        if len(rendered) > MAX_OUTPUT_CHARS:
            raise SessionError("session summary exceeds the display limit")
        return rendered


def list_sessions(root: Path, limit: int, cursor: str | None) -> str:
    client = AppServerClient(root)
    try:
        client.connect()
        params: dict[str, Any] = {
            "limit": limit,
            "useStateDbOnly": True,
            "sourceKinds": [
                "exec",
                "vscode",
                "cli",
                "appServer",
                "subAgent",
                "subAgentReview",
                "subAgentCompact",
                "subAgentThreadSpawn",
                "subAgentOther",
                "unknown",
            ],
        }
        if cursor:
            params["cursor"] = cursor[:500]
        response = client.request("thread/list", params)
    finally:
        client.close()
    if not isinstance(response, dict) or not isinstance(response.get("data"), list):
        raise SessionError("Codex app-server returned an invalid session list")
    sessions = [
        selected_fields(
            thread,
            ("id", "name", "preview", "cwd", "model", "reasoningEffort", "updatedAt", "status", "source"),
        )
        for thread in response["data"]
        if isinstance(thread, dict)
    ]
    session_statuses = {
        row["id"]: row["status"]
        for row in sessions
        if isinstance(row.get("id"), str) and "status" in row
    }
    jobs = recent_job_rows(root, session_statuses)
    jobs_by_session: dict[str, dict[str, Any]] = {}
    for row in jobs:  # rows are newest first; keep the newest resumed job per session
        session_id = row.get("sessionId")
        if session_id:
            jobs_by_session.setdefault(session_id, row)
    for row in sessions:
        job = jobs_by_session.get(row.get("id"))
        if job:
            row["job"] = job
    next_cursor = text_field(response.get("nextCursor"), 500)
    return bounded_output(
        {"sessions": sessions, "jobs": jobs, "nextCursor": next_cursor},
        ("jobs", "sessions"),
    )


def show_session(root: Path, session_id: str, limit: int) -> str:
    session_id = validate_session_id(session_id)
    client = AppServerClient(root)
    try:
        client.connect()
        metadata = client.request("thread/read", {"threadId": session_id})
        turns_response = client.request("thread/turns/list", {"threadId": session_id, "limit": limit})
    finally:
        client.close()
    if not isinstance(metadata, dict) or not isinstance(metadata.get("thread"), dict):
        raise SessionError("Codex app-server returned an invalid session")
    if not isinstance(turns_response, dict) or not isinstance(turns_response.get("data"), list):
        raise SessionError("Codex app-server returned invalid session turns")

    thread = selected_fields(
        metadata["thread"],
        ("id", "name", "preview", "cwd", "model", "reasoningEffort", "updatedAt", "status", "source"),
    )
    matching_job = next(
        (row for row in recent_job_rows(root, {session_id: thread.get("status")}) if row.get("sessionId") == session_id),
        None,
    )
    if matching_job:
        thread["job"] = matching_job
    turns = []
    for turn in turns_response["data"]:
        if not isinstance(turn, dict):
            continue
        selected_turn = selected_fields(
            turn, ("id", "status", "startedAt", "completedAt", "durationMs")
        )
        error = turn.get("error")
        if isinstance(error, dict):
            message = text_field(error.get("message"), 300)
            if message:
                selected_turn["error"] = message
        items = turn.get("items")
        if isinstance(items, list):
            selected_turn["items"] = [
                selected
                for selected in (selected_item(item) for item in items[-6:])
                if selected is not None
            ]
        turns.append(selected_turn)
    next_cursor = text_field(turns_response.get("nextCursor"), 500)
    return bounded_output(
        {"session": thread, "turns": turns, "nextCursor": next_cursor},
        ("turns",),
    )


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(prog="michi-codex-sessions")
    commands = result.add_subparsers(dest="command", required=True)
    list_cmd = commands.add_parser("list", help="list recent Codex sessions")
    list_cmd.add_argument("--limit", type=int, default=20)
    list_cmd.add_argument("--cursor")
    show_cmd = commands.add_parser("show", help="show one session and its recent turns")
    show_cmd.add_argument("session_id")
    show_cmd.add_argument("--limit", type=int, default=5)
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        root = configured_root()
        if args.command == "list":
            if not 1 <= args.limit <= 100:
                raise SessionError("list limit must be between 1 and 100")
            print(list_sessions(root, args.limit, args.cursor))
        elif args.command == "show":
            if not 1 <= args.limit <= 20:
                raise SessionError("show limit must be between 1 and 20")
            print(show_session(root, args.session_id, args.limit))
        else:
            raise SessionError("unsupported command")
        return 0
    except SessionError as exc:
        print(f"michi-codex-sessions: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
