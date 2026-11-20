"""Publication replacement and authenticated ancestry preparation."""
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from maintenance import cli, gate
from maintenance.common import Blocked, REPOSITORY

BASE, HEAD, APP = "a" * 40, "b" * 40, "maintenance[bot]"


class PublicationTests(unittest.TestCase):
    def test_only_untouched_older_app_candidates_are_closed(self):
        old = {"number": 4, "user": {"login": APP}, "base": {"sha": "c" * 40},
               "body": f"Candidate: `{HEAD}`",
               "head": {"sha": HEAD, "ref": "maintenance/old", "repo": {"full_name": REPOSITORY}}}
        commit = {"sha": HEAD, "parents": [{"sha": BASE}]}
        human = {**old, "number": 3, "user": {"login": "owner"}}
        for commits, allowed in (([commit], True), ([commit, commit], False)):
            api = mock.Mock()
            api.pages.side_effect = [[human, old, {**old, "number": 5}], commits]
            if allowed:
                cli.close_superseded(api, {"branch_prefix": "maintenance/"}, 5, APP)
                api.request.assert_called_once_with("PATCH", f"/repos/{REPOSITORY}/pulls/4", {"state": "closed"})
            else:
                with self.assertRaisesRegex(Blocked, "was modified"):
                    cli.close_superseded(api, {"branch_prefix": "maintenance/"}, 5, APP)
                api.request.assert_not_called()
        modified = {**old, "body": f"Candidate: `{'d' * 40}`"}
        api.pages.side_effect = [[modified], [commit]]
        with self.assertRaisesRegex(Blocked, "was modified"):
            cli.close_superseded(api, {"branch_prefix": "maintenance/"}, 5, APP)

    def test_prepare_carries_verified_ancestry_in_native_identity(self):
        policy = {"holds": {"certificate": {"revision": BASE, "required_nixpkgs_commits": [BASE]}}}
        api = mock.Mock()
        api.get.return_value = {"status": "ahead"}
        expected = gate.identity("hash", 4, BASE, HEAD)
        with tempfile.TemporaryDirectory() as temp:
            args = SimpleNamespace(trusted=Path(temp), output=Path(temp) / "identity.json")
            with mock.patch.object(cli, "load_policy", return_value=(policy, "hash")), \
                 mock.patch.object(cli, "env_identity", return_value=expected), \
                 mock.patch.object(cli, "github", return_value=api), \
                 mock.patch.object(gate, "verify_pr"), \
                 mock.patch.object(gate, "verify_sources", return_value={"nixpkgs": HEAD}):
                cli.prepare(args)
            result = json.loads(args.output.read_text())
        self.assertEqual(result["ancestry"], {"certificate": {
            "revision": HEAD, "required_commits": [BASE], "verified": True}})
        api.get.assert_called_once_with(f"/repos/NixOS/nixpkgs/compare/{BASE}...{HEAD}?per_page=1&page=2")
        for status in ("behind", "diverged", None):
            api.get.return_value = {"status": status}
            with self.assertRaisesRegex(Blocked, "not an ancestor"):
                gate.verify_ancestry(api, policy, HEAD)


if __name__ == "__main__":
    unittest.main()
