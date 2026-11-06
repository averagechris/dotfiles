import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from maintenance import notify


class MaintenanceNotifyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.state = Path(self.temp.name) / "state"
        self.event = {"kind": "failed", "fingerprint": "job:abc-v1", "summary": "Build failed"}

    def tearDown(self):
        self.temp.cleanup()

    def test_dedupe_and_quiet_routine_events(self):
        self.assertTrue(notify.queue(self.state, self.event, now=100))
        self.assertFalse(notify.queue(self.state, self.event, now=101))
        for kind in ("noop", "merged", "recovered"):
            quiet = {**self.event, "kind": kind, "fingerprint": f"{kind}-x"}
            self.assertFalse(notify.queue(self.state, quiet, now=100))

    def test_success_silence_and_owner_routing(self):
        self.assertTrue(notify.queue(self.state, {**self.event, "chat_id": "999"}, now=100))
        calls = []

        def sent(token, owner, message):
            calls.append((token, owner, message))
            return "sent", None

        result = notify.deliver(self.state, "secret-token", "12345", now=120, transport=sent)
        self.assertEqual(result, {"sent": 1, "retried": 0, "blocked": 0, "skipped": 0})
        self.assertEqual(calls[0][0:2], ("secret-token", "12345"))
        self.assertNotIn("999", calls[0][2])
        self.assertEqual(len(list((self.state / "sent").glob("*.json"))), 1)
        record = next((self.state / "sent").glob("*.json")).read_text()
        self.assertNotIn("secret-token", record)

    def test_retry_and_retry_after(self):
        notify.queue(self.state, self.event, now=100)
        result = notify.deliver(self.state, "token", "8", now=100,
                                transport=lambda *_: ("retry", 300))
        self.assertEqual(result["retried"], 1)
        record = next((self.state / "pending").glob("*.json"))
        self.assertEqual(json.loads(record.read_text())["next_attempt"], 400)
        called = []
        result = notify.deliver(self.state, "token", "8", now=399,
                                transport=lambda *_: called.append(True) or ("sent", None))
        self.assertEqual(result["skipped"], 1)
        self.assertEqual(called, [])
        result = notify.deliver(self.state, "token", "8", now=400,
                                transport=lambda *_: ("sent", None))
        self.assertEqual(result["sent"], 1)

    def test_interrupted_inflight_is_recovered(self):
        notify.queue(self.state, self.event, now=100)
        pending = next((self.state / "pending").glob("*.json"))
        pending.replace(self.state / "inflight" / pending.name)
        routed = []
        result = notify.deliver(self.state, "token", "731", now=200,
                                transport=lambda token, owner, message: routed.append(owner) or ("sent", None))
        self.assertEqual(result["sent"], 1)
        self.assertEqual(routed, ["731"])

    def test_same_fingerprint_reminder_after_24_hours(self):
        notify.queue(self.state, self.event, now=100)
        notify.deliver(self.state, "token", "7", now=100, transport=lambda *_: ("sent", None))
        self.assertFalse(notify.queue(self.state, self.event, now=100 + 86399))
        self.assertTrue(notify.queue(self.state, self.event, now=100 + 86400))

    def test_permanent_failure_has_safe_visible_receipt(self):
        notify.queue(self.state, self.event, now=100)
        result = notify.deliver(self.state, "token", "7", now=101,
                                transport=lambda *_: ("blocked", None))
        self.assertEqual(result["blocked"], 1)
        record = json.loads(next((self.state / "blocked").glob("*.json")).read_text())
        self.assertIn("permanently", record["receipt"])
        self.assertNotIn("last_error", record)
        self.assertFalse(notify.queue(self.state, self.event, now=200000))
        result = notify.deliver(self.state, "token", "7", now=200000,
                                transport=lambda *_: self.fail("permanently rejected alert must not resend"))
        self.assertEqual(result["blocked"], 1, "a permanent failure must remain visible on later ticks")

    def test_cli_exposes_delivery_failure_without_secret_or_event_content(self):
        for kind in ("retried", "blocked"):
            result = {"sent": 0, "retried": 0, "blocked": 0, "skipped": 0, kind: 1}
            output = io.StringIO()
            with mock.patch.dict("os.environ", {"BOT_TOKEN": "secret-token", "TG_OWNER_ID": "7"}), \
                 mock.patch.object(notify, "deliver", return_value=result), contextlib.redirect_stdout(output):
                code = notify.main(["deliver", "--state", str(self.state)])
            self.assertEqual(code, 1)
            self.assertEqual(json.loads(output.getvalue()), result)
            self.assertNotIn("secret-token", output.getvalue())

    def test_credentials_and_content_are_not_exposed(self):
        self.assertTrue(notify.queue(self.state, {**self.event, "summary": "See /etc/private/key"}, now=100))
        delivered = []
        notify.deliver(self.state, "token-never-store", "42", now=101,
                       transport=lambda token, owner, text: delivered.append(text) or ("sent", None))
        self.assertNotIn("/etc/private/key", delivered[0])
        for folder in ("pending", "inflight", "sent", "blocked"):
            for path in (self.state / folder).glob("*.json"):
                self.assertNotIn("token-never-store", path.read_text())
        self.assertEqual(notify.message_for({**self.event, "summary": "x" * 6000}).__len__(), 4096)
        with self.assertRaises(notify.NotifyError):
            notify.deliver(self.state, "token", "0", transport=lambda *_: ("sent", None))


if __name__ == "__main__":
    unittest.main()
