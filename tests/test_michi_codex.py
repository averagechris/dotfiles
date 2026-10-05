import importlib.util
import json
import os
import stat
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
from http.server import BaseHTTPRequestHandler, HTTPServer
import unittest
from unittest import mock
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "michi-codex.py"
SPEC = importlib.util.spec_from_file_location("michi_codex", SCRIPT)
michi = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(michi)

SESSIONS_SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "michi-codex-sessions.py"
SESSIONS_SPEC = importlib.util.spec_from_file_location("michi_codex_sessions", SESSIONS_SCRIPT)
sessions = importlib.util.module_from_spec(SESSIONS_SPEC)
SESSIONS_SPEC.loader.exec_module(sessions)

NOTIFY_SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "michi-codex-notify.py"
NOTIFY_SPEC = importlib.util.spec_from_file_location("michi_codex_notify", NOTIFY_SCRIPT)
notifier = importlib.util.module_from_spec(NOTIFY_SPEC)
NOTIFY_SPEC.loader.exec_module(notifier)


FAKE_CODEX = r'''#!__PYTHON__
import json
import os
import sys
import time
from pathlib import Path

args = sys.argv[1:]
record = Path(__RECORD_PATH__)
if args[:2] == ["login", "status"]:
    with record.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps({"args": args, "env": dict(os.environ)}) + "\n")
    print("Logged in using ChatGPT")
    raise SystemExit(0)

with record.open("a", encoding="utf-8") as stream:
    stream.write(json.dumps({"args": args, "env": dict(os.environ)}) + "\n")
last_message = Path(args[args.index("--output-last-message") + 1])
prompt = sys.stdin.read()
print(json.dumps({"type": "thread.started", "thread_id": "123e4567-e89b-12d3-a456-426614174000"}), flush=True)
if prompt.startswith("sleep:"):
    time.sleep(float(prompt.split(":", 1)[1]))
if prompt.startswith("outcome:"):
    outcome = prompt.split(":", 1)[1].splitlines()[0]
    last_message.write_text("Implemented the requested change.\nChecks: unit suite passed.\nOutcome: " + outcome, encoding="utf-8")
else:
    last_message.write_text("Codex result: " + prompt, encoding="utf-8")
if prompt.startswith("fail:"):
    raise SystemExit(int(prompt.split(":", 1)[1]))
'''


class MichiCodexTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / "owner-workspace"
        self.root.mkdir(mode=0o700)
        self.root = self.root.resolve(strict=True)
        self.project = self.root / "project"
        self.project.mkdir()
        self.record = Path(self.temp.name) / "codex-invocations.jsonl"
        source = FAKE_CODEX.replace("__PYTHON__", sys.executable).replace(
            "__RECORD_PATH__", repr(str(self.record))
        )
        self.binary = Path(self.temp.name) / "fake-codex"
        self.binary.write_text(source, encoding="utf-8")
        self.binary.chmod(0o700)
        self.old_env = os.environ.copy()
        os.environ["MICHI_CODEX_ROOT"] = str(self.root)
        os.environ["MICHI_CODEX_BINARY"] = str(self.binary)
        os.environ["PATH"] = self.old_env.get("PATH", os.defpath)
        os.environ["LANG"] = "C.UTF-8"
        os.environ["GH_TOKEN"] = "test-token"
        os.environ["TG_OWNER_ID"] = "123456789"
        os.environ["BOT_TOKEN"] = "synthetic-bot-secret"
        os.environ["OPENAI_API_KEY"] = "must-not-reach-codex"
        os.environ["GIT_CONFIG_COUNT"] = "1"
        os.environ["GIT_CONFIG_KEY_0"] = "credential.https://github.com.helper"
        os.environ["GIT_CONFIG_VALUE_0"] = "!unused-gh auth git-credential"
        os.environ["GIT_CONFIG_KEY_1"] = "credential.helper"
        os.environ["GIT_CONFIG_VALUE_1"] = "!must-not-run"
        os.environ["WORKTOKEN"] = "must-not-reach-codex"

    def tearDown(self):
        os.environ.clear()
        os.environ.update(self.old_env)
        self.temp.cleanup()

    def submit(self, prompt, model="sol", resume=None, cwd=None, reasoning=None, notify_owner=False):
        return michi.submit(
            self.root,
            str(self.binary),
            str(cwd or self.project),
            prompt,
            model,
            resume,
            reasoning,
            notify_owner,
        )

    def test_git_credential_environment_is_allowlisted_and_host_scoped(self):
        helper = Path(self.temp.name) / "fake-gh"
        helper.write_text("#!/bin/sh\nprintf 'username=synthetic\\npassword=synthetic-token\\n\\n'\n", encoding="utf-8")
        helper.chmod(0o700)
        env = michi.safe_environment(self.root)
        env["GIT_CONFIG_VALUE_0"] = f"!{helper} auth git-credential"

        result = subprocess.run(
            ["git", "credential", "fill"],
            input="protocol=https\nhost=github.com\n\n",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            check=True,
        )

        self.assertIn("username=synthetic", result.stdout)
        self.assertIn("password=synthetic-token", result.stdout)
        env["GIT_TERMINAL_PROMPT"] = "0"
        other_host = subprocess.run(
            ["git", "credential", "fill"],
            input="protocol=https\nhost=example.com\n\n",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            check=False,
        )
        self.assertNotEqual(other_host.returncode, 0)
        self.assertNotIn("synthetic-token", other_host.stdout)
        self.assertEqual(env["GIT_CONFIG_COUNT"], "1")
        self.assertEqual(env["GIT_CONFIG_KEY_0"], "credential.https://github.com.helper")
        self.assertNotIn("GIT_CONFIG_KEY_1", env)
        self.assertNotIn("GIT_CONFIG_VALUE_1", env)
        self.assertNotIn("WORKTOKEN", env)
        self.assertEqual(env["GH_TOKEN"], "test-token")

    def run_worker(self):
        errors = []

        def run():
            try:
                michi.run_worker(self.root, str(self.binary))
            except BaseException as exc:
                errors.append(exc)

        thread = threading.Thread(target=run, daemon=True)
        thread.start()
        return thread, errors

    def wait_for_status(self, job, expected, timeout=5):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            _, state = michi.load_state(self.root, job)
            if state.get("status") == expected:
                return state
            time.sleep(0.02)
        self.fail(f"job {job} did not reach {expected}")

    def test_submit_is_private_and_cwd_is_confined(self):
        job = self.submit("change the project")
        directory, state = michi.load_state(self.root, job)
        self.assertEqual(state["status"], "queued")
        self.assertFalse((michi.job_dir(self.root, job) / "followup.json").exists())
        self.assertEqual(state["model"], "sol")
        self.assertEqual(state["reasoning"], "low")
        request = michi.read_json(directory / "request.json")
        self.assertEqual((request["model"], request["reasoning"]), ("sol", "low"))
        self.assertIn("gpt-6.1-sol (low reasoning)", michi.state_summary(state))
        self.assertEqual(stat.S_IMODE(directory.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE((directory / "request.json").stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE((michi.paths(self.root)["pending"] / f"{job}.json").stat().st_mode), 0o600)

        with tempfile.TemporaryDirectory() as outside:
            with self.assertRaisesRegex(michi.JobError, "inside the owner workspace"):
                self.submit("bad cwd", cwd=Path(outside))
        for blocked in (self.root / ".codex", self.root / ".codex-jobs"):
            blocked.mkdir(exist_ok=True)
            with self.assertRaisesRegex(michi.JobError, "cannot be inside"):
                self.submit("bad cwd", cwd=blocked)

    def test_model_defaults_and_invalid_reasoning(self):
        luna = self.submit("bounded task", model="luna")
        _, luna_state = michi.load_state(self.root, luna)
        self.assertEqual((luna_state["model"], luna_state["reasoning"]), ("luna", "medium"))
        self.assertIn("gpt-6-luna (medium reasoning)", michi.state_summary(luna_state))

        sol_override = self.submit("use more reasoning", reasoning="high")
        _, sol_state = michi.load_state(self.root, sol_override)
        self.assertEqual((sol_state["model"], sol_state["reasoning"]), ("sol", "high"))

        with self.assertRaisesRegex(michi.JobError, "Luna does not support ultra"):
            self.submit("unsupported effort", model="luna", reasoning="ultra")
        self.assertEqual(len(list(michi.paths(self.root)["jobs"].iterdir())), 2)

    def test_auth_check_requires_the_dedicated_chatgpt_profile(self):
        authenticated, message = michi.auth_check(self.root, str(self.binary))
        self.assertTrue(authenticated)
        self.assertIn("dedicated owner-workspace profile", message)
        auth_call = json.loads(self.record.read_text(encoding="utf-8").splitlines()[0])
        self.assertEqual(auth_call["args"][:2], ["login", "status"])
        self.assertIn('cli_auth_credentials_store="file"', auth_call["args"])
        self.assertIn('cli_auth_credentials_store="file"', auth_call["args"])
        self.assertEqual(auth_call["env"]["CODEX_HOME"], str(self.root / ".codex"))

        api_key_binary = Path(self.temp.name) / "api-key-codex"
        api_key_binary.write_text(
            self.binary.read_text(encoding="utf-8").replace(
                "Logged in using ChatGPT", "Logged in using API key sk-test-secret"
            ),
            encoding="utf-8",
        )
        api_key_binary.chmod(0o700)
        authenticated, message = michi.auth_check(self.root, str(api_key_binary))
        self.assertFalse(authenticated)
        self.assertNotIn("sk-test-secret", message)

    def test_worker_completes_job_and_forwards_only_allowed_credentials(self):
        job = self.submit("implement the change", model="sol")
        thread, errors = self.run_worker()
        thread.join(timeout=5)
        self.assertFalse(thread.is_alive())
        self.assertEqual(errors, [])
        _, state = michi.load_state(self.root, job)
        self.assertEqual(state["status"], "complete")
        self.assertEqual(state["session_id"], "123e4567-e89b-12d3-a456-426614174000")
        result = michi.command_result(self.root, job)
        self.assertIn("Codex result: implement the change", result)
        self.assertIn("Full result file:", result)
        call = next(
            item
            for item in map(json.loads, self.record.read_text(encoding="utf-8").splitlines())
            if item["args"][:1] == ["exec"]
        )
        self.assertIn("gpt-6.1-sol", call["args"])
        self.assertIn('model_reasoning_effort="low"', call["args"])
        self.assertIn("--skip-git-repo-check", call["args"])
        self.assertEqual(call["env"].get("GH_TOKEN"), "test-token")
        self.assertNotIn("OPENAI_API_KEY", call["env"])
        self.assertNotIn("BOT_TOKEN", call["env"])
        self.assertNotIn("TG_OWNER_ID", call["env"])
        self.assertEqual(call["env"]["CODEX_HOME"], str(self.root / ".codex"))

    def test_resume_requires_session_and_passes_recorded_session(self):
        first = self.submit("first request")
        thread, errors = self.run_worker()
        thread.join(timeout=5)
        self.assertEqual(errors, [])
        elsewhere = self.root / "another-project"
        elsewhere.mkdir()
        with self.assertRaisesRegex(michi.JobError, "same working directory"):
            self.submit("switch project", resume=first, cwd=elsewhere)
        second = self.submit("continue the work", resume=first)
        self.assertEqual(michi.load_state(self.root, second)[1]["session_id"],
                         "123e4567-e89b-12d3-a456-426614174000")
        thread, errors = self.run_worker()
        thread.join(timeout=5)
        self.assertEqual(errors, [])
        _, state = michi.load_state(self.root, second)
        self.assertEqual(state["status"], "complete")
        calls = [
            item["args"]
            for item in map(json.loads, self.record.read_text(encoding="utf-8").splitlines())
            if item["args"][:1] == ["exec"]
        ]
        self.assertIn("resume", calls[1])
        self.assertIn("123e4567-e89b-12d3-a456-426614174000", calls[1])

    def test_cancel_stops_running_codex_job(self):
        job = self.submit("sleep:30")
        thread, errors = self.run_worker()
        self.wait_for_status(job, "running")
        self.assertIn("Cancellation requested", michi.command_cancel(self.root, job))
        thread.join(timeout=5)
        self.assertFalse(thread.is_alive())
        self.assertEqual(errors, [])
        _, state = michi.load_state(self.root, job)
        self.assertEqual(state["status"], "cancelled")

    def test_failure_and_worker_restart_are_recorded(self):
        failed = self.submit("fail:7")
        thread, errors = self.run_worker()
        thread.join(timeout=5)
        self.assertEqual(errors, [])
        _, state = michi.load_state(self.root, failed)
        self.assertEqual(state["status"], "failed")
        self.assertEqual(state["exit_code"], 7)

        interrupted = "a" * 32
        directory = michi.paths(self.root)["jobs"] / interrupted
        directory.mkdir(mode=0o700)
        michi.write_state(directory, {"id": interrupted, "status": "running"})
        self.assertIn("interrupted", michi.command_status(self.root, interrupted))
        _, state = michi.load_state(self.root, interrupted)
        self.assertEqual(state["status"], "interrupted")
        state["status"] = "running"
        michi.write_state(directory, state)
        thread, errors = self.run_worker()
        thread.join(timeout=5)
        self.assertEqual(errors, [])
        _, state = michi.load_state(self.root, interrupted)
        self.assertEqual(state["status"], "interrupted")

    def test_worker_rechecks_chatgpt_auth_before_running_queued_job(self):
        job = self.submit("should not run")
        self.binary.write_text(
            self.binary.read_text(encoding="utf-8").replace(
                "Logged in using ChatGPT", "Logged in using API key sk-test-secret"
            ),
            encoding="utf-8",
        )
        self.binary.chmod(0o700)
        thread, errors = self.run_worker()
        thread.join(timeout=5)
        self.assertEqual(errors, [])
        _, state = michi.load_state(self.root, job)
        self.assertEqual(state["status"], "failed")
        self.assertIn("not authenticated", state["error"])
        calls = [
            item["args"]
            for item in map(json.loads, self.record.read_text(encoding="utf-8").splitlines())
        ]
        self.assertFalse(any(args[:1] == ["exec"] for args in calls))

    def test_followup_opt_in_worker_delivery_and_restart_do_not_repeat_acknowledged_send(self):
        job = self.submit("outcome:complete", notify_owner=True)
        directory, _ = michi.load_state(self.root, job)
        followup = michi.read_json(directory / "followup.json")
        self.assertEqual(followup["destination"], "owner")
        self.assertEqual(followup["owner_id"], "123456789")
        prompt = michi.read_json(directory / "request.json")["prompt"]
        self.assertIn("Outcome: needs_input", prompt)
        self.assertIn("actual changes, checks, and unresolved issues", prompt)

        thread, errors = self.run_worker()
        thread.join(timeout=5)
        self.assertEqual(errors, [])
        _, state = michi.load_state(self.root, job)
        self.assertEqual(state["status"], "complete")
        self.assertEqual(state["session_id"], "123e4567-e89b-12d3-a456-426614174000")

        server, received = self.telegram_server([{"status": 200, "body": {"ok": True, "result": {"message_id": 91}}}])
        try:
            with mock.patch.object(notifier, "API_URL", self.server_url(server)):
                self.assertEqual(notifier.notify_once(self.root, "bot-secret", "123456789", now=100), 1)
                self.assertEqual(notifier.notify_once(self.root, "bot-secret", "123456789", now=101), 0)
            self.assertEqual(len(received), 1)
            payload = received[0][1]
            self.assertEqual(payload["chat_id"], "123456789")
            self.assertIn(job, payload["text"])
            self.assertIn("Checks: unit suite passed", payload["text"])
            self.assertNotIn("Outcome: complete", payload["text"])
            notification = michi.read_json(directory / "notification.json")
            self.assertEqual(notification["status"], "sent")
            self.assertEqual(notification["message_id"], 91)
            self.assertEqual(notification["session_id"], state["session_id"])
            self.assertNotIn("bot-secret", (directory / "notification.json").read_text())
        finally:
            server.shutdown()
            server.server_close()

    def test_followup_429_retry_is_durable_and_non_owner_id_is_rejected(self):
        job = self.submit("outcome:needs_input", notify_owner=True)
        thread, errors = self.run_worker()
        thread.join(timeout=5)
        self.assertEqual(errors, [])
        directory, state = michi.load_state(self.root, job)
        self.assertEqual(state["status"], "needs_input")

        server, received = self.telegram_server([
            {"status": 500, "body": {"ok": False}},
            {"status": 429, "body": {"ok": False, "parameters": {"retry_after": 7}}},
            {"status": 200, "body": {"ok": True, "result": {"message_id": 92}}},
        ])
        try:
            with mock.patch.object(notifier, "API_URL", self.server_url(server)):
                self.assertEqual(notifier.notify_once(self.root, "bot-secret", "123456789", now=100), 0)
                pending = michi.read_json(directory / "notification.json")
                self.assertEqual((pending["status"], pending["retry_at"]), ("pending", 115))
                self.assertEqual(notifier.notify_once(self.root, "bot-secret", "123456789", now=114), 0)
                self.assertEqual(notifier.notify_once(self.root, "bot-secret", "123456789", now=115), 0)
                pending = michi.read_json(directory / "notification.json")
                self.assertEqual((pending["status"], pending["retry_at"]), ("pending", 122))
                self.assertEqual(notifier.notify_once(self.root, "bot-secret", "123456789", now=122), 1)
            self.assertEqual(len(received), 3)
            self.assertIn("needs your input", received[2][1]["text"])
            self.assertNotIn("Outcome: needs_input", received[2][1]["text"])
        finally:
            server.shutdown()
            server.server_close()
        with mock.patch.dict(os.environ, {"BOT_TOKEN": "x", "TG_OWNER_ID": "-1", "MICHI_CODEX_ROOT": str(self.root)}):
            with self.assertRaisesRegex(notifier.NotifyError, "positive integer"):
                notifier.configuration()

    def test_followup_cancel_failure_and_stale_running_are_terminal_notifications(self):
        failed = self.submit("fail:7", notify_owner=True)
        thread, errors = self.run_worker()
        thread.join(timeout=5)
        self.assertEqual(errors, [])
        _, failed_state = michi.load_state(self.root, failed)
        self.assertEqual(failed_state["status"], "failed")

        cancelled = self.submit("sleep:30", notify_owner=True)
        thread, errors = self.run_worker()
        self.wait_for_status(cancelled, "running")
        michi.command_cancel(self.root, cancelled)
        thread.join(timeout=5)
        self.assertEqual(errors, [])
        _, cancelled_state = michi.load_state(self.root, cancelled)
        self.assertEqual(cancelled_state["status"], "cancelled", cancelled_state)
        self.assertEqual(cancelled_state["session_id"], "123e4567-e89b-12d3-a456-426614174000")

        orphan = self.submit("outcome:complete", notify_owner=True)
        orphan_dir, orphan_state = michi.load_state(self.root, orphan)
        orphan_state.update(status="running", session_id=None)
        michi.write_state(orphan_dir, orphan_state)
        (orphan_dir / "events.jsonl").write_text(json.dumps({
            "type": "thread.started", "thread_id": "123e4567-e89b-12d3-a456-426614174000",
        }) + "\n")
        server, received = self.telegram_server([
            {"status": 200, "body": {"ok": True, "result": {"message_id": 93}}},
            {"status": 200, "body": {"ok": True, "result": {"message_id": 94}}},
            {"status": 200, "body": {"ok": True, "result": {"message_id": 95}}},
        ])
        try:
            with mock.patch.object(notifier, "API_URL", self.server_url(server)):
                self.assertEqual(notifier.notify_once(self.root, "bot-secret", "123456789", now=200), 3)
            _, orphan_state = michi.load_state(self.root, orphan)
            self.assertEqual(orphan_state["status"], "interrupted")
            self.assertEqual(orphan_state["session_id"], "123e4567-e89b-12d3-a456-426614174000")
            messages = [entry[1]["text"] for entry in received]
            self.assertTrue(any(f"Codex job {failed} failed" in text for text in messages))
            self.assertTrue(any(f"Codex job {cancelled} was cancelled" in text for text in messages))
            self.assertTrue(any(f"Codex job {orphan} was interrupted" in text for text in messages))
        finally:
            server.shutdown()
            server.server_close()

    def test_changed_owner_configuration_never_reroutes_existing_followup(self):
        job = self.submit("outcome:complete", notify_owner=True)
        thread, errors = self.run_worker()
        thread.join(timeout=5)
        self.assertEqual(errors, [])
        directory = michi.job_dir(self.root, job)
        server, received = self.telegram_server([])
        try:
            with mock.patch.object(notifier, "API_URL", self.server_url(server)):
                self.assertEqual(notifier.notify_once(self.root, "bot-secret", "999", now=10), 0)
            self.assertEqual(received, [])
            record = michi.read_json(directory / "notification.json")
            self.assertEqual(record["status"], "halted")
            self.assertNotIn("999", json.dumps(record))
        finally:
            server.shutdown()
            server.server_close()

    def test_completed_followup_is_delivered_while_worker_lock_is_busy(self):
        job = self.submit("outcome:complete", notify_owner=True)
        thread, errors = self.run_worker()
        thread.join(timeout=5)
        self.assertEqual(errors, [])
        worker_lock = michi.acquire_worker_lock(self.root)
        self.assertIsNotNone(worker_lock)
        server, received = self.telegram_server([
            {"status": 200, "body": {"ok": True, "result": {"message_id": 96}}},
        ])
        try:
            with mock.patch.object(notifier, "API_URL", self.server_url(server)):
                self.assertEqual(notifier.notify_once(self.root, "bot-secret", "123456789", now=12), 1)
            self.assertEqual(len(received), 1)
            self.assertIn(job, received[0][1]["text"])
        finally:
            worker_lock.close()
            server.shutdown()
            server.server_close()

    def test_telegram_text_limit_counts_utf16_code_units(self):
        job = "a" * 32
        directory = Path(self.temp.name)
        (directory / "result.txt").write_text("🐈" * 5000, encoding="utf-8")
        message = notifier.message_for(job, {"status": "complete"}, directory)
        self.assertLessEqual(notifier.utf16_length(message), 4096)
        self.assertIn("[Result shortened for Telegram.]", message)

    def test_network_failure_survives_restart_and_retries_successfully(self):
        job = self.submit("outcome:complete", notify_owner=True)
        thread, errors = self.run_worker()
        thread.join(timeout=5)
        self.assertEqual(errors, [])
        directory = michi.job_dir(self.root, job)
        with mock.patch.object(notifier.urllib.request, "urlopen", side_effect=urllib.error.URLError("private network detail")):
            self.assertEqual(notifier.notify_once(self.root, "bot-secret", "123456789", now=50), 0)
        retry = michi.read_json(directory / "notification.json")
        self.assertEqual((retry["status"], retry["retry_at"]), ("pending", 65))
        self.assertNotIn("private network detail", json.dumps(retry))

        server, received = self.telegram_server([
            {"status": 200, "body": {"ok": True, "result": {"message_id": 97}}},
        ])
        try:
            with mock.patch.object(notifier, "API_URL", self.server_url(server)):
                self.assertEqual(notifier.notify_once(self.root, "bot-secret", "123456789", now=65), 1)
            self.assertEqual(len(received), 1)
            self.assertEqual(michi.read_json(directory / "notification.json")["status"], "sent")
        finally:
            server.shutdown()
            server.server_close()

    def test_permanent_telegram_rejection_is_recorded_without_repeating(self):
        job = self.submit("outcome:complete", notify_owner=True)
        thread, errors = self.run_worker()
        thread.join(timeout=5)
        self.assertEqual(errors, [])
        server, received = self.telegram_server([
            {"status": 403, "body": {"ok": False, "description": "private rejection reason"}},
        ])
        try:
            with mock.patch.object(notifier, "API_URL", self.server_url(server)):
                self.assertEqual(notifier.notify_once(self.root, "bot-secret", "123456789", now=80), 0)
                self.assertEqual(notifier.notify_once(self.root, "bot-secret", "123456789", now=81), 0)
            self.assertEqual(len(received), 1)
            record = michi.read_json(michi.job_dir(self.root, job) / "notification.json")
            self.assertEqual(record["status"], "halted")
            self.assertNotIn("private rejection reason", json.dumps(record))
        finally:
            server.shutdown()
            server.server_close()

    def test_invalid_owner_submission_creates_no_job_or_pending_request(self):
        with mock.patch.dict(os.environ, {"TG_OWNER_ID": "0"}):
            with self.assertRaisesRegex(michi.JobError, "positive integer"):
                self.submit("should not queue", notify_owner=True)
        jobs_root = self.root / ".codex-jobs"
        self.assertFalse(jobs_root.exists())

    def telegram_server(self, responses):
        received = []
        class Handler(BaseHTTPRequestHandler):
            queue = list(responses)
            records = received
            def do_POST(self):
                size = int(self.headers.get("Content-Length", "0"))
                self.records.append((self.path, json.loads(self.rfile.read(size))))
                response = self.queue.pop(0)
                body = json.dumps(response["body"]).encode()
                self.send_response(response["status"])
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            def log_message(self, *_args):
                pass
        server = HTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        return server, received

    @staticmethod
    def server_url(server):
        return f"http://127.0.0.1:{server.server_port}"

    def test_status_does_not_overwrite_completion_after_a_stale_read(self):
        job = self.submit("bounded task")
        directory, state = michi.load_state(self.root, job)
        state["status"] = "running"
        michi.write_state(directory, state)
        acquire = michi.acquire_worker_lock

        def finish_then_acquire(root):
            state["status"] = "complete"
            michi.write_state(directory, state)
            return acquire(root)

        with mock.patch.object(michi, "acquire_worker_lock", side_effect=finish_then_acquire):
            self.assertIn("complete", michi.command_status(self.root, job))
        self.assertEqual(michi.load_state(self.root, job)[1]["status"], "complete")

    def test_invalid_job_ids_are_rejected(self):
        with self.assertRaisesRegex(michi.JobError, "job ID"):
            michi.command_status(self.root, "../state")

    def test_wait_is_bounded_to_twenty_seconds(self):
        job = self.submit("queued")
        self.assertEqual(michi.main(["wait", job, "--seconds", "21"]), 2)

    @unittest.skipUnless(
        os.environ.get("RUN_SLOW_MICHI_CODEX_TESTS") == "1",
        "takes 61 seconds to prove the worker outlives the shell deadline",
    )
    def test_job_outlives_a_sixty_second_shell_window(self):
        job = self.submit("sleep:61")
        thread, errors = self.run_worker()
        self.wait_for_status(job, "running")
        started = time.monotonic()
        # A shell caller has already received the queued job ID; only the
        # separate worker waits for Codex to finish.
        output = michi.command_status(self.root, job, wait_seconds=0)
        self.assertIn("running", output)
        self.assertLess(time.monotonic() - started, 60)
        thread.join(timeout=70)
        self.assertFalse(thread.is_alive())
        self.assertEqual(errors, [])
        _, state = michi.load_state(self.root, job)
        self.assertEqual(state["status"], "complete")


class FakeSessionWebSocket:
    class WebSocketException(Exception):
        pass

    def __init__(self, messages):
        self.messages = list(messages)
        self.sent = []
        self.closed = False

    def send(self, message):
        self.sent.append(json.loads(message))

    def recv(self):
        if not self.messages:
            raise TimeoutError("no response")
        return json.dumps(self.messages.pop(0))

    def settimeout(self, timeout):
        self.timeout = timeout

    def close(self):
        self.closed = True


class FakeSessionClient:
    def __init__(self, root, responses):
        self.responses = responses
        self.requests = []

    def connect(self):
        pass

    def request(self, method, params):
        self.requests.append((method, params))
        return self.responses[method]

    def close(self):
        pass


class MichiCodexSessionsTests(unittest.TestCase):
    SESSION_ID = "123e4567-e89b-12d3-a456-426614174000"

    def test_rpc_ignores_interleaved_notifications_and_times_out_cleanly(self):
        client = sessions.AppServerClient(Path("/tmp"), FakeSessionWebSocket.__class__)
        websocket = FakeSessionWebSocket([
            {"jsonrpc": "2.0", "method": "event"},
            {"jsonrpc": "2.0", "id": 1, "result": {"ok": True}},
        ])
        client.websocket = websocket
        client.websocket_module = type("WSModule", (), {"WebSocketException": FakeSessionWebSocket.WebSocketException})
        self.assertEqual(client.request("thread/list", {}), {"ok": True})
        self.assertEqual(websocket.sent[0]["method"], "thread/list")

        websocket.messages.clear()
        with self.assertRaisesRegex(sessions.SessionError, "timed out"):
            client.request("thread/list", {})
        client.close()
        self.assertTrue(websocket.closed)

    def test_running_job_enriches_not_loaded_session_and_list_filters_fields(self):
        with tempfile.TemporaryDirectory(dir="/tmp", prefix="mcs") as temp:
            root = Path(temp)
            older_dir = root / ".codex-jobs" / "jobs" / ("b" * 32)
            older_dir.mkdir(parents=True)
            (older_dir / "state.json").write_text(json.dumps({
                "id": "b" * 32,
                "status": "complete",
                "session_id": self.SESSION_ID,
            }))
            job_id = "a" * 32
            job_dir = root / ".codex-jobs" / "jobs" / job_id
            job_dir.mkdir(parents=True)
            (job_dir / "state.json").write_text(json.dumps({
                "id": job_id,
                "status": "running",
                "model": "sol",
                "reasoning": "low",
                "session_id": None,
            }))
            (job_dir / "events.jsonl").write_text(json.dumps({
                "type": "thread.started", "thread_id": self.SESSION_ID,
            }) + "\n")
            fake = FakeSessionClient(root, {"thread/list": {
                "data": [{
                    "id": self.SESSION_ID,
                    "name": "A task",
                    "status": {"type": "notLoaded"},
                    "privateTranscript": "must not appear",
                }],
                "nextCursor": None,
            }})
            with mock.patch.object(sessions, "AppServerClient", return_value=fake):
                rendered = sessions.list_sessions(root, 10, None)
            payload = json.loads(rendered)
            session = payload["sessions"][0]
            self.assertEqual(session["status"], "notLoaded")
            self.assertEqual(session["job"]["jobStatus"], "running")
            self.assertEqual(session["job"]["modelName"], "gpt-6.1-sol")
            self.assertEqual(session["job"]["codexSessionStatus"], "notLoaded")
            self.assertNotIn("privateTranscript", rendered)
            self.assertEqual(fake.requests[0][0], "thread/list")
            self.assertTrue(fake.requests[0][1]["useStateDbOnly"])
            self.assertIn("exec", fake.requests[0][1]["sourceKinds"])

    def test_show_returns_bounded_turns_and_preserves_active_status(self):
        with tempfile.TemporaryDirectory(dir="/tmp", prefix="mcs") as temp:
            root = Path(temp)
            fake = FakeSessionClient(root, {
                "thread/read": {"thread": {
                    "id": self.SESSION_ID,
                    "status": {"type": "active", "activeFlags": ["waitingOnApproval", "secret"]},
                    "privateTranscript": "must not appear",
                }},
                "thread/turns/list": {"data": [{
                    "id": "turn-1", "status": "completed",
                    "items": [
                        {"type": "agentMessage", "text": "A" * 2000, "private": "hidden"},
                        {"type": "unknownTool", "secret": "hidden"},
                    ] * 3,
                } for _ in range(20)]},
            })
            with mock.patch.object(sessions, "AppServerClient", return_value=fake):
                rendered = sessions.show_session(root, self.SESSION_ID, 5)
            self.assertLessEqual(len(rendered), sessions.MAX_OUTPUT_CHARS)
            payload = json.loads(rendered)
            self.assertTrue(payload["truncated"])
            self.assertLess(len(payload["turns"]), 20)
            self.assertEqual(payload["session"]["status"], {
                "type": "active", "activeFlags": ["waitingOnApproval"],
            })
            self.assertEqual(payload["turns"][0]["items"][0]["type"], "agentMessage")
            self.assertNotIn("privateTranscript", rendered)
            self.assertNotIn("hidden", rendered)
            self.assertEqual([method for method, _ in fake.requests], ["thread/read", "thread/turns/list"])

    def test_invalid_session_and_socket_alias_are_rejected_before_connect(self):
        with tempfile.TemporaryDirectory(dir="/tmp", prefix="mcs") as temp:
            root = Path(temp)
            with self.assertRaisesRegex(sessions.SessionError, "lowercase Codex UUID"):
                sessions.show_session(root, "../invalid", 1)
            alias = root / ".codex" / "michi-app-server.sock"
            alias.parent.mkdir()
            alias.symlink_to("/tmp/codex-daemon-999999/" + "a" * 64)
            with self.assertRaisesRegex(sessions.SessionError, "invalid target"):
                sessions.app_server_socket(root)


if __name__ == "__main__":
    unittest.main()
