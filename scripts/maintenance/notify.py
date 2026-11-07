#!/usr/bin/env python3
"""Private, durable outbox for owner-only maintenance alerts."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Callable

from maintenance.common import Blocked, atomic_json, digest, dumps, read_json

API_URL = "https://api.telegram.org"
MAX_UTF16 = 4096
BASE_RETRY_SECONDS = 15
MAX_RETRY_SECONDS = 3600
MAX_ATTEMPTS_PER_RUN = 8
KINDS = {"failed", "needs_owner", "interrupted", "watchdog", "recovered", "merged", "noop"}
QUIET_KINDS = {"recovered", "merged", "noop"}
FINGERPRINT_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$")
LOCAL_PATH_RE = re.compile(r"(?<![A-Za-z0-9:/])(?:/(?:[^\s/]+/)*[^\s\]\[()<>\"']+|[A-Za-z]:\\[^\s\]\[()<>\"']+)")
CONTROL_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")


class NotifyError(Exception):
    """Safe, user-displayable configuration or input error."""


def _private_dir(path: Path) -> None:
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    if path.is_symlink() or not path.is_dir():
        raise NotifyError("state directory is not a private directory")
    os.chmod(path, 0o700)


def _layout(state_dir: Path) -> dict[str, Path]:
    _private_dir(state_dir)
    result = {}
    for name in ("pending", "inflight", "sent", "blocked"):
        path = state_dir / name
        _private_dir(path)
        result[name] = path
    return result


def _read(path: Path) -> dict[str, Any]:
    try:
        value = read_json(path)
    except (Blocked, OSError, ValueError, TypeError):
        raise NotifyError("invalid outbox record") from None
    if not isinstance(value, dict):
        raise NotifyError("invalid outbox record")
    return value


def _lock(state_dir: Path) -> Any:
    path = state_dir / "outbox.lock"
    fd = os.open(path, os.O_CREAT | os.O_RDWR | getattr(os, "O_NOFOLLOW", 0), 0o600)
    os.fchmod(fd, 0o600)
    stream = os.fdopen(fd, "r+")
    fcntl.flock(stream.fileno(), fcntl.LOCK_EX)
    return stream


def _validate_event(event: Any) -> dict[str, Any]:
    if not isinstance(event, dict) or event.get("kind") not in KINDS:
        raise NotifyError("event kind is invalid")
    fingerprint = event.get("fingerprint")
    summary = event.get("summary")
    if not isinstance(fingerprint, str) or not FINGERPRINT_RE.fullmatch(fingerprint):
        raise NotifyError("event fingerprint is invalid")
    if not isinstance(summary, str) or len(summary) > 20000:
        raise NotifyError("event summary is invalid")
    result = {"kind": event["kind"], "fingerprint": fingerprint, "summary": summary}
    url = event.get("url")
    if url is not None:
        if not isinstance(url, str) or len(url) > 2048 or not re.fullmatch(r"https?://[^\s<>]+", url):
            raise NotifyError("event URL is invalid")
        result["url"] = url
    return result


def queue(state_dir: str | Path, event: dict[str, Any], now: int | None = None) -> bool:
    """Durably enqueue one materially distinct alert; return whether it was queued."""
    state_dir = Path(state_dir)
    dirs = _layout(state_dir)
    event = _validate_event(event)
    if event["kind"] in QUIET_KINDS:
        return False
    current = int(time.time() if now is None else now)
    key = digest(event["fingerprint"].encode("ascii"))
    with _lock(state_dir):
        for dirname in ("pending", "inflight", "sent", "blocked"):
            path = dirs[dirname] / f"{key}.json"
            if not path.exists():
                continue
            record = _read(path)
            if dirname in ("pending", "inflight"):
                return False
            delivered_at = record.get("sent_at", record.get("blocked_at", current))
            if isinstance(delivered_at, int) and current - delivered_at < 24 * 60 * 60:
                return False
        record = {"event": event, "fingerprint": event["fingerprint"], "queued_at": current,
                  "attempts": 0, "next_attempt": current}
        atomic_json(dirs["pending"] / f"{key}.json", record)
        return True


def _utf16_length(value: str) -> int:
    return sum(2 if ord(char) > 0xFFFF else 1 for char in value)


def _truncate_utf16(value: str, limit: int) -> str:
    out, used = [], 0
    for char in value:
        width = 2 if ord(char) > 0xFFFF else 1
        if used + width > limit:
            break
        out.append(char)
        used += width
    return "".join(out)


def message_for(event: dict[str, Any]) -> str:
    """Render bounded plain text while removing local filesystem paths."""
    event = _validate_event(event)
    summary = CONTROL_RE.sub("", event["summary"])
    summary = LOCAL_PATH_RE.sub("[local path]", summary).strip()
    labels = {"failed": "Maintenance failed", "needs_owner": "Maintenance needs you",
              "interrupted": "Maintenance was interrupted", "watchdog": "Maintenance watchdog alert"}
    message = labels.get(event["kind"], "Maintenance alert") + ":\n" + summary
    if event.get("url"):
        message += "\n" + event["url"]
    if _utf16_length(message) > MAX_UTF16:
        suffix = "\n…"
        message = _truncate_utf16(message, MAX_UTF16 - _utf16_length(suffix)).rstrip() + suffix
    return message


def _retry_delay(attempt: int, retry_after: int | None = None) -> int:
    if retry_after is not None:
        return max(1, int(retry_after))
    return min(MAX_RETRY_SECONDS, BASE_RETRY_SECONDS * (2 ** min(max(attempt - 1, 0), 8)))


def _send(token: str, owner_id: str, text: str) -> tuple[str, int | None]:
    payload = json.dumps({"chat_id": owner_id, "text": text}).encode("utf-8")
    req = urllib.request.Request(f"{API_URL}/bot{token}/sendMessage", data=payload,
                                 headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            data = json.loads(response.read().decode("utf-8"))
            if isinstance(data, dict) and data.get("ok") is True:
                return "sent", None
            return "retry", None
    except urllib.error.HTTPError as exc:
        retry_after = None
        if exc.code == 429:
            try:
                data = json.loads(exc.read().decode("utf-8"))
                retry_after = int(data.get("parameters", {}).get("retry_after", 1))
            except (ValueError, TypeError, AttributeError, json.JSONDecodeError):
                retry_after = 1
        code = exc.code
        exc.close()
        if code == 429 or code >= 500:
            return "retry", retry_after
        return "blocked", None
    except (OSError, TimeoutError, urllib.error.URLError, json.JSONDecodeError, ValueError, TypeError):
        return "retry", None


def _credential(name: str) -> str:
    value = os.environ.get(name)
    if value:
        return value.strip()
    directory = os.environ.get("CREDENTIALS_DIRECTORY")
    if directory:
        try:
            return (Path(directory) / ("bot-token" if name == "BOT_TOKEN" else "owner-id")).read_text(encoding="utf-8").strip()
        except OSError:
            pass
    raise NotifyError(f"{name} is not configured")


def _validate_credentials(token: str, owner_id: str) -> tuple[str, str]:
    if not token or "\n" in token or "\r" in token:
        raise NotifyError("bot token is not configured")
    if not owner_id.isascii() or not owner_id.isdecimal() or int(owner_id) <= 0:
        raise NotifyError("owner ID must be a positive integer")
    return token, str(int(owner_id))


def deliver(state_dir: str | Path, bot_token: str, owner_id: str, now: int | None = None,
            transport: Callable[[str, str, str], tuple[str, int | None]] | None = None) -> dict[str, int]:
    """Send due alerts to the configured owner, recovering interrupted work."""
    state_dir = Path(state_dir)
    dirs = _layout(state_dir)
    bot_token, owner_id = _validate_credentials(bot_token, owner_id)
    current = int(time.time() if now is None else now)
    transport = transport or _send
    with _lock(state_dir):
        stats = {"sent": 0, "retried": 0, "blocked": len(list(dirs["blocked"].glob("*.json"))), "skipped": 0}
        # A process may have exited at any point after claiming. The Telegram API
        # has no idempotency key, so the safest durable recovery is to retry it.
        for path in list(dirs["inflight"].glob("*.json")):
            os.replace(path, dirs["pending"] / path.name)
        for path in sorted(dirs["pending"].glob("*.json")):
            record = _read(path)
            if int(record.get("next_attempt", 0)) > current:
                stats["skipped"] += 1
                continue
            inflight = dirs["inflight"] / path.name
            os.replace(path, inflight)
            record = _read(inflight)
            try:
                outcome, retry_after = transport(bot_token, owner_id, message_for(record["event"]))
            except Exception:
                outcome, retry_after = "retry", None
            if outcome == "sent":
                record["sent_at"] = current
                record.pop("last_error", None)
                atomic_json(dirs["sent"] / path.name, record)
                inflight.unlink(missing_ok=True)
                blocked = dirs["blocked"] / path.name
                if blocked.exists():
                    blocked.unlink()
                    stats["blocked"] -= 1
                stats["sent"] += 1
            elif outcome == "blocked":
                record["blocked_at"] = current
                record["receipt"] = "Telegram rejected this alert permanently."
                previous_rejection = (dirs["blocked"] / path.name).exists()
                atomic_json(dirs["blocked"] / path.name, record)
                inflight.unlink(missing_ok=True)
                stats["blocked"] += int(not previous_rejection)
            else:
                record["attempts"] = int(record.get("attempts", 0)) + 1
                record["next_attempt"] = current + _retry_delay(record["attempts"], retry_after)
                atomic_json(dirs["pending"] / path.name, record)
                inflight.unlink(missing_ok=True)
                stats["retried"] += 1
                if stats["retried"] >= MAX_ATTEMPTS_PER_RUN:
                    break
    return stats


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    enqueue_parser = sub.add_parser("enqueue", help="enqueue one event from a JSON file")
    enqueue_parser.add_argument("--state", required=True, type=Path)
    enqueue_parser.add_argument("--event", required=True, type=Path)
    deliver_parser = sub.add_parser("deliver", help="deliver pending events to the configured owner")
    deliver_parser.add_argument("--state", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        if args.command == "enqueue":
            event = json.loads(args.event.read_text(encoding="utf-8"))
            queue(args.state, event)
            return 0
        token, owner = _validate_credentials(_credential("BOT_TOKEN"), _credential("TG_OWNER_ID"))
        result = deliver(args.state, token, owner)
        print(dumps(result))
        return int(bool(result["retried"] or result["blocked"]))
    except (NotifyError, OSError, json.JSONDecodeError):
        # Deliberately avoid rendering exception values, which may contain event
        # text, credential paths, or transport details.
        print("maintenance notifier could not complete the requested operation", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
