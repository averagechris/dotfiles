import importlib.util
import json
import os
import stat
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "michi-codex.py"
SPEC = importlib.util.spec_from_file_location("michi_codex", SCRIPT)
michi = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(michi)


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
        os.environ["OPENAI_API_KEY"] = "must-not-reach-codex"

    def tearDown(self):
        os.environ.clear()
        os.environ.update(self.old_env)
        self.temp.cleanup()

    def submit(self, prompt, model="luna", resume=None, cwd=None):
        return michi.submit(
            self.root,
            str(self.binary),
            str(cwd or self.project),
            prompt,
            model,
            resume,
        )

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
        self.assertIn('model_reasoning_effort="high"', call["args"])
        self.assertIn("--skip-git-repo-check", call["args"])
        self.assertEqual(call["env"].get("GH_TOKEN"), "test-token")
        self.assertNotIn("OPENAI_API_KEY", call["env"])
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


if __name__ == "__main__":
    unittest.main()
