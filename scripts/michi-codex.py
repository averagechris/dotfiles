#!/usr/bin/env python3
"""Queue and inspect private Codex jobs for Michi's owner workspace."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import re
import signal
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path
from typing import Any


JOB_TIMEOUT_SECONDS = 2 * 60 * 60
MAX_WAIT_SECONDS = 20
MAX_RESULT_CHARS = 12_000
POLL_SECONDS = 0.2
ID_RE = re.compile(r"^[0-9a-f]{32}$")
SESSION_UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)
MODELS = {
    "luna": ("gpt-6-luna", "medium", {"low", "medium", "high", "xhigh", "max"}),
    "sol": ("gpt-6.1-sol", "low", {"low", "medium", "high", "xhigh", "max", "ultra"}),
    "astra": ("gpt-6-astra", "low", {"low", "medium", "high", "xhigh", "max", "ultra"}),
}


class JobError(Exception):
    pass


def configured_root() -> Path:
    value = os.environ.get("MICHI_CODEX_ROOT")
    if not value:
        raise JobError("MICHI_CODEX_ROOT is not configured")
    root = Path(value).resolve(strict=True)
    if not root.is_dir():
        raise JobError("configured owner workspace is not a directory")
    return root


def configured_binary() -> str:
    value = os.environ.get("MICHI_CODEX_BINARY")
    if not value or not os.path.isabs(value) or not os.path.isfile(value) or not os.access(value, os.X_OK):
        raise JobError("MICHI_CODEX_BINARY must name the installed Codex CLI")
    return value


def private_directory(path: Path) -> Path:
    try:
        path.mkdir(mode=0o700, parents=True, exist_ok=True)
        info = path.lstat()
    except OSError as exc:
        raise JobError(f"cannot prepare private job directory: {exc}") from exc
    if not path.is_dir() or path.is_symlink() or info.st_uid != os.geteuid():
        raise JobError(f"unsafe job directory: {path}")
    os.chmod(path, 0o700)
    return path


def paths(root: Path) -> dict[str, Path]:
    base = private_directory(root / ".codex-jobs")
    jobs = private_directory(base / "jobs")
    pending = private_directory(base / "pending")
    return {
        "base": base,
        "jobs": jobs,
        "pending": pending,
        "lock": base / "worker.lock",
        "codex_home": private_directory(root / ".codex"),
    }


def job_id(value: str) -> str:
    if not ID_RE.fullmatch(value):
        raise JobError("job ID must be 32 lowercase hexadecimal characters")
    return value


def job_dir(root: Path, value: str) -> Path:
    return paths(root)["jobs"] / job_id(value)


def atomic_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
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
        try:
            temp.unlink()
        except FileNotFoundError:
            pass


def read_json(path: Path) -> dict[str, Any]:
    try:
        with path.open(encoding="utf-8") as stream:
            value = json.load(stream)
    except (OSError, json.JSONDecodeError) as exc:
        raise JobError(f"cannot read job record: {exc}") from exc
    if not isinstance(value, dict):
        raise JobError("invalid job record")
    return value


def load_state(root: Path, value: str) -> tuple[Path, dict[str, Any]]:
    directory = job_dir(root, value)
    if directory.is_symlink() or not directory.is_dir():
        raise JobError("job not found")
    return directory, read_json(directory / "state.json")


def write_state(directory: Path, state: dict[str, Any]) -> None:
    atomic_json(directory / "state.json", state)


def safe_environment(root: Path) -> dict[str, str]:
    env = {
        "HOME": str(root),
        "CODEX_HOME": str(root / ".codex"),
        "PATH": os.environ.get("PATH", "/run/current-system/sw/bin:/usr/bin:/bin"),
        "LANG": os.environ.get("LANG", "C.UTF-8"),
        "LC_ALL": os.environ.get("LC_ALL", "C.UTF-8"),
        "TERM": "dumb",
    }
    for name in ("GH_TOKEN", "SSL_CERT_FILE", "NIX_SSL_CERT_FILE"):
        if os.environ.get(name):
            env[name] = os.environ[name]
    return env


def auth_check(root: Path, binary: str) -> tuple[bool, str]:
    try:
        result = subprocess.run(
            [
                binary,
                "login",
                "status",
                "-c",
                'cli_auth_credentials_store="file"',
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
            env=safe_environment(root),
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False, "Codex authentication status could not be checked."
    status_text = f"{result.stdout}\n{result.stderr}"
    lowered = status_text.lower()
    authenticated = (
        result.returncode == 0
        and "logged in" in lowered
        and "chatgpt" in lowered
        and "api key" not in lowered
    )
    if authenticated:
        return True, "Codex is authenticated with the dedicated owner-workspace profile."
    return False, "Codex is not authenticated in the dedicated owner-workspace profile."


def validate_cwd(root: Path, value: str) -> Path:
    if not Path(value).is_absolute():
        raise JobError("working directory must be an absolute path inside the owner workspace")
    try:
        cwd = Path(value).resolve(strict=True)
    except OSError as exc:
        raise JobError(f"working directory is unavailable: {exc}") from exc
    if not cwd.is_dir() or not cwd.is_relative_to(root):
        raise JobError("working directory must be inside the owner workspace")
    relative = cwd.relative_to(root)
    if relative.parts and relative.parts[0] in {".codex", ".codex-jobs"}:
        raise JobError("working directory cannot be inside .codex or .codex-jobs")
    return cwd


def session_for_job(root: Path, value: str, cwd: Path) -> str:
    _, state = load_state(root, value)
    session = state.get("session_id")
    if not isinstance(session, str) or not SESSION_UUID_RE.fullmatch(session):
        raise JobError("that job has no recorded Codex session ID to resume")
    if state.get("cwd") != str(cwd):
        raise JobError("a resumed job must use the same working directory as its prior session")
    return session


def submit(
    root: Path,
    binary: str,
    cwd_value: str,
    prompt: str,
    model: str,
    resume_id: str | None,
    reasoning: str | None = None,
    notify_owner: bool = False,
) -> str:
    if not prompt.strip():
        raise JobError("prompt must not be empty")
    cwd = validate_cwd(root, cwd_value)
    if model not in MODELS:
        raise JobError("model must be luna, sol, or astra")
    _, default_reasoning, supported_reasoning = MODELS[model]
    effort = reasoning or default_reasoning
    if effort not in supported_reasoning:
        if effort == "ultra" and model == "luna":
            raise JobError("Luna does not support ultra reasoning")
        raise JobError("reasoning must be low, medium, high, xhigh, max, or ultra for Sol and Astra")
    resume_from = job_id(resume_id) if resume_id else None
    session_id = session_for_job(root, resume_from, cwd) if resume_from else None
    owner_id = None
    if notify_owner:
        owner_id = os.environ.get("TG_OWNER_ID", "")
        if not owner_id.isascii() or not owner_id.isdecimal() or int(owner_id) <= 0:
            raise JobError("TG_OWNER_ID must be a positive integer for owner follow-ups")
    authenticated, message = auth_check(root, binary)
    if not authenticated:
        raise JobError(message)

    layout = paths(root)
    value = uuid.uuid4().hex
    directory = layout["jobs"] / value
    private_directory(directory)
    state = {
        "id": value,
        "status": "queued",
        "created_at": int(time.time()),
        "cwd": str(cwd),
        "model": model,
        "reasoning": effort,
        "resume_from": resume_from,
        "session_id": session_id,
        "exit_code": None,
        "error": None,
    }
    if notify_owner:
        atomic_json(directory / "followup.json", {
            "version": 1,
            "destination": "owner",
            "owner_id": str(int(owner_id)),
            "created_at": int(time.time()),
        })
    write_state(directory, state)
    if notify_owner:
        prompt += (
            "\n\nFor this Michi follow-up job, end your final response with exactly one final line: "
            "Outcome: complete, Outcome: needs_input, or Outcome: failed. Use needs_input when "
            "the owner must answer or unblock the work. Report actual changes, checks, and unresolved issues."
        )
    atomic_json(directory / "request.json", {
        "id": value,
        "cwd": str(cwd),
        "prompt": prompt,
        "model": model,
        "reasoning": effort,
        "session_id": session_id,
    })
    pending_path = layout["pending"] / f"{value}.json"
    atomic_json(pending_path, {"id": value})
    return value


def worker_unit_authorized() -> bool:
    try:
        cgroups = Path("/proc/self/cgroup").read_text(encoding="utf-8")
    except OSError:
        return False
    return any("michi-codex-worker.service" in line for line in cgroups.splitlines())


def acquire_worker_lock(root: Path) -> Any:
    lock_path = paths(root)["lock"]
    fd = os.open(lock_path, os.O_CREAT | os.O_RDWR | getattr(os, "O_NOFOLLOW", 0), 0o600)
    os.fchmod(fd, 0o600)
    stream = os.fdopen(fd, "r+")
    try:
        fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        stream.close()
        return None
    return stream


def mark_orphaned_jobs(root: Path) -> None:
    for directory in paths(root)["jobs"].iterdir():
        if not ID_RE.fullmatch(directory.name) or directory.is_symlink() or not directory.is_dir():
            continue
        try:
            state = read_json(directory / "state.json")
        except JobError:
            continue
        if state.get("status") == "running":
            recover_session(directory, state)
            state["status"] = "interrupted"
            state["error"] = "Codex worker restarted while this job was running."
            state["finished_at"] = int(time.time())
            write_state(directory, state)


def codex_command(binary: str, request: dict[str, Any], directory: Path) -> list[str]:
    model_name = MODELS[request["model"]][0]
    effort = request.get("reasoning", MODELS[request["model"]][1])
    cmd = [binary, "exec", "--color", "never"]
    if request.get("session_id"):
        cmd.append("resume")
    cmd.extend([
        "--json",
        "--ignore-user-config",
        "-c", 'cli_auth_credentials_store="file"',
        "-c", 'approval_policy="never"',
        "-c", 'sandbox_mode="workspace-write"',
        "-c", 'allow_login_shell=false',
        "-c", "sandbox_workspace_write.network_access=true",
        "-c", "shell_environment_policy.ignore_default_excludes=true",
        "-c", 'agents.default_subagent_model="gpt-6-luna"',
        "-c", 'agents.default_subagent_reasoning_effort="medium"',
        "-m", model_name,
        "-c", f'model_reasoning_effort="{effort}"',
        "--skip-git-repo-check",
        "--output-last-message", str(directory / "result.txt"),
    ])
    if request.get("session_id"):
        cmd.append(request["session_id"])
    cmd.append("-")
    return cmd


def session_from_jsonl(path: Path) -> str | None:
    try:
        with path.open(encoding="utf-8", errors="replace") as stream:
            for line in stream:
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if not isinstance(event, dict):
                    continue
                if event.get("type") == "thread.started":
                    value = event.get("thread_id") or event.get("session_id")
                    if isinstance(value, str) and SESSION_UUID_RE.fullmatch(value):
                        return value
    except OSError:
        pass
    return None


def recover_session(directory: Path, state: dict[str, Any]) -> bool:
    session = state.get("session_id") or session_from_jsonl(directory / "events.jsonl")
    if isinstance(session, str) and SESSION_UUID_RE.fullmatch(session):
        changed = state.get("session_id") != session
        state["session_id"] = session
        return changed
    return False


def outcome_from_result(path: Path) -> str | None:
    try:
        tail = path.read_text(encoding="utf-8", errors="replace")[-1000:]
    except OSError:
        return None
    match = re.search(r"(?:^|\n)Outcome: (complete|needs_input|failed)\s*$", tail)
    return match.group(1) if match else None


def terminate_group(process: subprocess.Popen[bytes]) -> None:
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()


def execute_job(root: Path, binary: str, value: str) -> None:
    layout = paths(root)
    directory = layout["jobs"] / job_id(value)
    request_path = directory / "request.json"
    request = read_json(request_path)
    cwd = validate_cwd(root, request.get("cwd", ""))
    if request.get("model") not in MODELS:
        raise JobError("queued job has invalid model")
    model_name, default_reasoning, supported_reasoning = MODELS[request["model"]]
    reasoning = request.get("reasoning", default_reasoning)
    if reasoning not in supported_reasoning:
        raise JobError("queued job has invalid reasoning effort")
    if request.get("session_id") is not None and not SESSION_UUID_RE.fullmatch(str(request["session_id"])):
        raise JobError("queued job has invalid Codex session ID")
    state = read_json(directory / "state.json")
    if state.get("status") in {"cancelled", "complete", "needs_input", "failed", "interrupted"}:
        return
    state.update(model_name=model_name, reasoning=reasoning)
    if (directory / "cancel.flag").exists():
        state.update(status="cancelled", finished_at=int(time.time()))
        write_state(directory, state)
        return
    authenticated, message = auth_check(root, binary)
    if not authenticated:
        state.update(status="failed", error=message, finished_at=int(time.time()))
        write_state(directory, state)
        return

    state.update(status="running", started_at=int(time.time()), error=None)
    write_state(directory, state)
    prompt_path = directory / "prompt.txt"
    prompt_path.write_text(str(request.get("prompt", "")), encoding="utf-8")
    os.chmod(prompt_path, 0o600)
    stdout_path = directory / "events.jsonl"
    stderr_path = directory / "stderr.log"
    env = safe_environment(root)
    process: subprocess.Popen[bytes] | None = None
    try:
        with prompt_path.open("rb") as stdin, stdout_path.open("wb") as stdout, stderr_path.open("wb") as stderr:
            os.chmod(stdout_path, 0o600)
            os.chmod(stderr_path, 0o600)
            process = subprocess.Popen(
                codex_command(binary, request, directory),
                cwd=cwd,
                stdin=stdin,
                stdout=stdout,
                stderr=stderr,
                env=env,
                start_new_session=True,
                close_fds=True,
            )
            state.update(codex_pid=process.pid)
            write_state(directory, state)
            deadline = time.monotonic() + JOB_TIMEOUT_SECONDS
            while process.poll() is None:
                if recover_session(directory, state):
                    write_state(directory, state)
                if (directory / "cancel.flag").exists():
                    terminate_group(process)
                    recover_session(directory, state)
                    state.update(status="cancelled", error=None, finished_at=int(time.time()))
                    write_state(directory, state)
                    return
                if time.monotonic() >= deadline:
                    terminate_group(process)
                    recover_session(directory, state)
                    state.update(status="failed", error="Codex job exceeded the two-hour limit.", finished_at=int(time.time()))
                    write_state(directory, state)
                    return
                time.sleep(POLL_SECONDS)
            exit_code = process.returncode
        state["session_id"] = session_from_jsonl(stdout_path) or state.get("session_id") or request.get("session_id")
        if (directory / "cancel.flag").exists():
            state.update(status="cancelled", error=None, finished_at=int(time.time()))
            write_state(directory, state)
            return
        state["exit_code"] = exit_code
        state["finished_at"] = int(time.time())
        if exit_code == 0:
            outcome = outcome_from_result(directory / "result.txt") if (directory / "followup.json").is_file() else None
            state.update(status=outcome or "complete", error=None)
        else:
            state.update(status="failed", error=f"Codex exited with status {exit_code}.")
        write_state(directory, state)
    except Exception as exc:
        if process is not None and process.poll() is None:
            terminate_group(process)
        state.update(status="failed", error=f"Codex worker error: {type(exc).__name__}.", finished_at=int(time.time()))
        write_state(directory, state)


def run_worker(root: Path, binary: str) -> None:
    lock = acquire_worker_lock(root)
    if lock is None:
        return
    with lock:
        mark_orphaned_jobs(root)
        pending = paths(root)["pending"]
        while True:
            requests = sorted(pending.glob("*.json"))
            if not requests:
                return
            request_path = requests[0]
            value = request_path.stem
            if not ID_RE.fullmatch(value):
                request_path.unlink(missing_ok=True)
                continue
            directory = paths(root)["jobs"] / value
            try:
                directory.lstat()
            except FileNotFoundError:
                request_path.unlink(missing_ok=True)
                continue
            claimed = directory / "request.json"
            if not claimed.exists():
                request_path.unlink(missing_ok=True)
                continue
            request_path.unlink(missing_ok=True)
            try:
                execute_job(root, binary, value)
            except Exception as exc:
                state = read_json(directory / "state.json")
                if state.get("status") not in {"cancelled", "complete", "needs_input", "failed", "interrupted"}:
                    state.update(status="failed", error=f"Invalid queued job: {type(exc).__name__}.", finished_at=int(time.time()))
                    write_state(directory, state)


def state_summary(state: dict[str, Any]) -> str:
    status = state.get("status", "unknown")
    lines = [f"Job {state.get('id', '?')}: {status}"]
    if state.get("model"):
        model_name = state.get("model_name") or MODELS.get(state["model"], (state["model"],))[0]
        reasoning = state.get("reasoning")
        suffix = f" ({reasoning} reasoning)" if reasoning else ""
        lines.append(f"Model: {model_name}{suffix}")
    if state.get("session_id"):
        lines.append(f"Codex session: {state['session_id']}")
    if state.get("exit_code") is not None:
        lines.append(f"Exit status: {state['exit_code']}")
    if state.get("error"):
        lines.append(f"Detail: {state['error']}")
    return "\n".join(lines)


def command_status(root: Path, value: str, wait_seconds: int = 0) -> str:
    directory, state = load_state(root, value)
    deadline = time.monotonic() + wait_seconds
    while state.get("status") in {"queued", "running"} and time.monotonic() < deadline:
        time.sleep(min(POLL_SECONDS, deadline - time.monotonic()))
        state = read_json(directory / "state.json")
    if state.get("status") == "running":
        lock = acquire_worker_lock(root)
        if lock is not None:
            with lock:
                # The worker may have finished after the first state read.
                state = read_json(directory / "state.json")
                if state.get("status") == "running":
                    recover_session(directory, state)
                    state["status"] = "interrupted"
                    state["error"] = "Codex worker is no longer running."
                    state["finished_at"] = int(time.time())
                    write_state(directory, state)
    return state_summary(state)


def command_result(root: Path, value: str) -> str:
    directory, state = load_state(root, value)
    result_path = directory / "result.txt"
    if not result_path.is_file():
        raise JobError(f"no final Codex message is available yet\n{state_summary(state)}")
    try:
        with result_path.open(encoding="utf-8", errors="replace") as stream:
            result = stream.read(MAX_RESULT_CHARS + 1).strip()
    except OSError as exc:
        raise JobError(f"cannot read Codex result: {exc}") from exc
    if len(result) > MAX_RESULT_CHARS:
        result = result[:MAX_RESULT_CHARS] + "\n\n[display capped; full result: " + str(result_path) + "]"
    return f"{state_summary(state)}\nFull result file: {result_path}\n\n{result}"


def command_cancel(root: Path, value: str) -> str:
    directory, state = load_state(root, value)
    if state.get("status") not in {"queued", "running"}:
        return f"{state_summary(state)}\nThis job is already finished."
    marker = directory / "cancel.flag"
    fd = os.open(marker, os.O_CREAT | os.O_WRONLY | getattr(os, "O_NOFOLLOW", 0), 0o600)
    os.close(fd)
    os.chmod(marker, 0o600)
    return f"Cancellation requested.\n{state_summary(state)}"


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(prog="michi-codex")
    commands = result.add_subparsers(dest="command", required=True)
    commands.add_parser("auth-status")
    submit_cmd = commands.add_parser("submit")
    submit_cmd.add_argument("--cwd", required=True)
    submit_cmd.add_argument("--prompt", required=True)
    submit_cmd.add_argument("--model", choices=sorted(MODELS), default="sol")
    submit_cmd.add_argument(
        "--reasoning",
        choices=("low", "medium", "high", "xhigh", "max", "ultra"),
    )
    submit_cmd.add_argument("--resume")
    submit_cmd.add_argument("--notify-owner", action="store_true")
    for name in ("status", "result", "cancel"):
        sub = commands.add_parser(name)
        sub.add_argument("id")
    wait_cmd = commands.add_parser("wait")
    wait_cmd.add_argument("id")
    wait_cmd.add_argument("--seconds", type=int, default=10)
    commands.add_parser("_worker", help=argparse.SUPPRESS)
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        root = configured_root()
        binary = configured_binary()
        paths(root)
        if args.command == "auth-status":
            authenticated, message = auth_check(root, binary)
            print(message)
            return 0 if authenticated else 1
        if args.command == "submit":
            value = submit(root, binary, args.cwd, args.prompt, args.model, args.resume, args.reasoning, args.notify_owner)
            print(f"Queued Codex job {value}. Use michi-codex status {value} to check progress.")
            return 0
        if args.command == "status":
            print(command_status(root, args.id))
            return 0
        if args.command == "wait":
            if not 0 <= args.seconds <= MAX_WAIT_SECONDS:
                raise JobError(f"wait duration must be between 0 and {MAX_WAIT_SECONDS} seconds")
            print(command_status(root, args.id, args.seconds))
            return 0
        if args.command == "result":
            print(command_result(root, args.id))
            return 0
        if args.command == "cancel":
            print(command_cancel(root, args.id))
            return 0
        if args.command == "_worker":
            if not worker_unit_authorized():
                raise JobError("worker mode is only available inside michi-codex-worker.service")
            run_worker(root, binary)
            return 0
        raise JobError("unsupported command")
    except JobError as exc:
        print(f"michi-codex: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
