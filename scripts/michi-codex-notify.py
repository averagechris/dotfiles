#!/usr/bin/env python3
"""Deliver durable final follow-ups for explicitly enrolled Michi Codex jobs."""

from __future__ import annotations

import fcntl
import json
import os
import re
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


API_URL = "https://api.telegram.org"
MAX_UTF16 = 4096
BASE_RETRY_SECONDS = 15
MAX_RETRY_SECONDS = 3600
MAX_ATTEMPTS_PER_RUN = 8
ID_RE = re.compile(r"^[0-9a-f]{32}$")
SESSION_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")


class NotifyError(Exception):
    pass


def configuration() -> tuple[Path, str, str]:
    root_value = os.environ.get("MICHI_CODEX_ROOT")
    token = os.environ.get("BOT_TOKEN", "")
    owner = os.environ.get("TG_OWNER_ID", "")
    if not root_value:
        raise NotifyError("MICHI_CODEX_ROOT is not configured")
    root = Path(root_value).resolve(strict=True)
    if not root.is_dir():
        raise NotifyError("configured owner workspace is not a directory")
    if not token or "\n" in token:
        raise NotifyError("BOT_TOKEN is not configured")
    if not owner.isascii() or not owner.isdecimal() or int(owner) <= 0:
        raise NotifyError("TG_OWNER_ID must be a positive integer")
    return root, token, str(int(owner))


def atomic_json(path: Path, value: dict[str, Any]) -> None:
    fd, temp_name = tempfile.mkstemp(prefix=".write-", dir=path.parent)
    temp = Path(temp_name)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(value, stream, ensure_ascii=False, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, path)
        os.chmod(path, 0o600)
    finally:
        temp.unlink(missing_ok=True)


def read_json(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as stream:
        value = json.load(stream)
    if not isinstance(value, dict):
        raise NotifyError("invalid private job record")
    return value


def lock_file(path: Path) -> Any | None:
    fd = os.open(path, os.O_CREAT | os.O_RDWR | getattr(os, "O_NOFOLLOW", 0), 0o600)
    os.fchmod(fd, 0o600)
    stream = os.fdopen(fd, "r+")
    try:
        fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        stream.close()
        return None
    return stream


def session_from_events(path: Path) -> str | None:
    try:
        with path.open(encoding="utf-8", errors="replace") as stream:
            for line in stream:
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if isinstance(event, dict) and event.get("type") == "thread.started":
                    session = event.get("thread_id") or event.get("session_id")
                    if isinstance(session, str) and SESSION_RE.fullmatch(session):
                        return session
    except OSError:
        pass
    return None


def reconcile_orphans(root: Path, base: Path) -> bool:
    """Mark stale running jobs only while holding the worker's own lock."""
    worker_lock = lock_file(base / "worker.lock")
    if worker_lock is None:
        return False
    try:
        for directory in (base / "jobs").iterdir():
            if not ID_RE.fullmatch(directory.name) or directory.is_symlink() or not directory.is_dir():
                continue
            try:
                state = read_json(directory / "state.json")
            except (OSError, json.JSONDecodeError, NotifyError):
                continue
            if state.get("status") == "running":
                session = state.get("session_id") or session_from_events(directory / "events.jsonl")
                if isinstance(session, str) and SESSION_RE.fullmatch(session):
                    state["session_id"] = session
                state.update(
                    status="interrupted",
                    error="Codex worker restarted while this job was running.",
                    finished_at=int(time.time()),
                )
                atomic_json(directory / "state.json", state)
    finally:
        worker_lock.close()
    return True


def utf16_length(value: str) -> int:
    return sum(2 if ord(char) > 0xFFFF else 1 for char in value)


def truncate_utf16(value: str, limit: int) -> str:
    used = 0
    output = []
    for char in value:
        width = 2 if ord(char) > 0xFFFF else 1
        if used + width > limit:
            break
        output.append(char)
        used += width
    return "".join(output)


def message_for(state: dict[str, Any], directory: Path) -> str:
    status = state.get("status")
    if status == "complete":
        lead = ""
    elif status == "needs_input":
        lead = "I need your input to continue."
    elif status == "failed":
        lead = "The task failed."
    elif status == "cancelled":
        lead = "The task was cancelled."
    elif status == "interrupted":
        lead = "The task was interrupted before it finished."
    else:
        raise NotifyError("job is not in a terminal state")
    result = ""
    try:
        result = (directory / "result.txt").read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        pass
    result = re.sub(r"(?:\n)?Outcome: (?:complete|needs_input|failed)\s*$", "", result).rstrip()
    if status == "complete":
        message = result or "The task completed, but no final answer was saved."
    else:
        message = lead
        if result:
            if status in {"cancelled", "interrupted"}:
                message += "\n\nThe saved response may be incomplete or out of date:\n"
            else:
                message += "\n\n"
            message += result
        else:
            message += "\n\nNo final answer was saved."
        error = state.get("error")
        if error:
            if "two-hour limit" in str(error):
                reason = "The task exceeded its time limit."
            elif "worker restarted" in str(error):
                reason = "The task stopped after a restart before it finished."
            elif "not authenticated" in str(error):
                reason = "Codex could not start because its account is not signed in."
            elif "exited with status " in str(error):
                code = re.search(r"exited with status (\d+)", str(error))
                reason = f"The task process exited with status {code.group(1)}." if code else "The task did not finish successfully."
            else:
                reason = "The task stopped because of an internal error."
            message += "\n\n" + reason
    if utf16_length(message) > MAX_UTF16:
        suffix = "\n\n[Result shortened for Telegram.]"
        message = truncate_utf16(message, max(0, MAX_UTF16 - utf16_length(suffix))).rstrip() + suffix
    return message


def retry_delay(attempt: int, retry_after: int | None = None) -> int:
    if retry_after is not None:
        # Telegram's explicit cooldown takes precedence over our backoff cap.
        return max(1, retry_after)
    return min(MAX_RETRY_SECONDS, BASE_RETRY_SECONDS * (2 ** min(max(attempt - 1, 0), 8)))


def send(token: str, owner_id: str, text: str) -> tuple[str, int | None, int | None]:
    payload = json.dumps({"chat_id": owner_id, "text": text}).encode("utf-8")
    request = urllib.request.Request(
        f"{API_URL}/bot{token}/sendMessage",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            data = json.loads(response.read().decode("utf-8"))
            result = data.get("result") if isinstance(data, dict) and data.get("ok") is True else None
            message_id = result.get("message_id") if isinstance(result, dict) else None
            if not isinstance(message_id, int) or isinstance(message_id, bool):
                return "retry", None, None
            return "sent", message_id, None
    except urllib.error.HTTPError as exc:
        if exc.code == 429:
            retry_after = None
            try:
                data = json.loads(exc.read().decode("utf-8"))
                retry_after = int(data.get("parameters", {}).get("retry_after", 0))
            except (ValueError, TypeError, AttributeError, json.JSONDecodeError):
                pass
            finally:
                exc.close()
            return "retry", None, retry_after
        code = exc.code
        exc.close()
        if code >= 500:
            return "retry", None, None
        return "halted", None, None
    except (OSError, TimeoutError, json.JSONDecodeError, urllib.error.URLError, ValueError, TypeError, AttributeError):
        return "retry", None, None


def notify_once(root: Path, token: str, owner_id: str, now: int | None = None) -> int:
    base = root / ".codex-jobs"
    jobs = base / "jobs"
    if base.is_symlink() or not jobs.is_dir() or jobs.is_symlink():
        return 0
    notify_lock = lock_file(base / "notify.lock")
    if notify_lock is None:
        return 0
    sent_count = 0
    try:
        reconcile_orphans(root, base)
        current = int(time.time()) if now is None else now
        attempts_this_run = 0
        for directory in sorted(jobs.iterdir()):
            if attempts_this_run >= MAX_ATTEMPTS_PER_RUN:
                break
            if not ID_RE.fullmatch(directory.name) or directory.is_symlink() or not directory.is_dir():
                continue
            followup_path = directory / "followup.json"
            if followup_path.is_symlink() or not followup_path.is_file():
                continue
            try:
                followup = read_json(followup_path)
                state = read_json(directory / "state.json")
            except (OSError, json.JSONDecodeError, NotifyError):
                continue
            if followup.get("version") != 1 or followup.get("destination") != "owner":
                continue
            enrolled_owner = followup.get("owner_id")
            if not isinstance(enrolled_owner, str) or not enrolled_owner.isascii() or not enrolled_owner.isdecimal() or int(enrolled_owner) <= 0:
                continue
            if str(int(enrolled_owner)) != owner_id:
                notification_path = directory / "notification.json"
                try:
                    prior = read_json(notification_path) if notification_path.exists() else {"attempts": 0}
                    if prior.get("status") not in {"sent", "halted"}:
                        prior.update(status="halted", error="Configured owner does not match enrolled destination.")
                        atomic_json(notification_path, prior)
                except (OSError, json.JSONDecodeError, NotifyError):
                    pass
                continue
            status = state.get("status")
            if status not in {"complete", "needs_input", "failed", "cancelled", "interrupted"}:
                continue
            notification_path = directory / "notification.json"
            if notification_path.is_symlink():
                continue
            try:
                notification = read_json(notification_path) if notification_path.exists() else {
                    "status": "pending", "attempts": 0,
                }
            except (OSError, json.JSONDecodeError, NotifyError):
                continue
            if notification.get("status") in {"sent", "halted"}:
                continue
            if notification.get("retry_at", 0) > current:
                continue
            attempts = int(notification.get("attempts", 0)) + 1
            notification.update(status="sending", attempts=attempts, session_id=state.get("session_id"))
            notification.pop("retry_at", None)
            atomic_json(notification_path, notification)
            attempts_this_run += 1
            result, message_id, retry_after = send(token, owner_id, message_for(state, directory))
            if result == "sent":
                notification.update(status="sent", message_id=message_id, sent_at=current)
                notification.pop("retry_at", None)
                notification.pop("error", None)
                sent_count += 1
            elif result == "halted":
                notification.update(status="halted", error="Telegram rejected this notification.")
            else:
                notification.update(
                    status="pending",
                    retry_at=current + retry_delay(attempts, retry_after),
                    error="Telegram delivery will be retried.",
                )
            atomic_json(notification_path, notification)
    finally:
        notify_lock.close()
    return sent_count


def main() -> int:
    try:
        root, token, owner_id = configuration()
        notify_once(root, token, owner_id)
        return 0
    except (NotifyError, OSError) as exc:
        # Errors intentionally omit exception text: it can contain private paths.
        print(f"michi-codex-notify: {type(exc).__name__}", file=__import__("sys").stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
