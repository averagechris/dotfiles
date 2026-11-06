"""Static trust-boundary checks for the GitHub maintenance workflow graph."""
from __future__ import annotations

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"
FILES = {
    "candidate": "maintenance-candidate.yml",
    "validate": "maintenance-validate.yml",
    "decide": "maintenance-decide.yml",
    "heartbeat": "maintenance-heartbeat.yml",
    "watchdog": "maintenance-watchdog.yml",
    "attest": "maintenance-attest.yml",
}
PINS = {
    "actions/checkout": "11d5960a326750d5838078e36cf38b85af677262",
    "cachix/install-nix-action": "75c75c31ebece974e48ebc36b4ad125bd97bd97b",
    "actions/upload-artifact": "ea165f8d65b6e75b540449e92b4886f43607fa02",
    "actions/download-artifact": "d3f86a106a0bac45b974a628896c90dbdf5c8093",
    "actions/create-github-app-token": "fee1f7d63c2ff003460e3d139729b119787bc349",
    "actions/cache/restore": "0057852bfaa89a56745cba8c7296529d2fc39830",
    "actions/cache/save": "0057852bfaa89a56745cba8c7296529d2fc39830",
}


def workflow(name: str) -> str:
    return (WORKFLOWS / FILES[name]).read_text(encoding="utf-8")


def job_block(source: str, name: str) -> str:
    """Return an indented job block without needing a third-party YAML parser."""
    match = re.search(rf"(?m)^  {re.escape(name)}:\n((?:^    .*\n|^\n)*)", source)
    if not match:
        raise AssertionError(f"job {name!r} not found")
    return match.group(0)


class MaintenanceWorkflowBoundaryTests(unittest.TestCase):
    def test_workflows_exist_and_actions_are_immutable_pinned(self):
        self.assertEqual(set(FILES), {p.stem.removeprefix("maintenance-") for p in WORKFLOWS.glob("maintenance-*.yml")})
        for name in FILES:
            source = workflow(name)
            for action, revision in PINS.items():
                if action in source:
                    self.assertIn(f"uses: {action}@{revision}", source, name)
                    self.assertNotRegex(source, rf"uses: {re.escape(action)}@(?:v\d|main|master)\b", name)
            for checkout in re.findall(r"(?ms)^      - name:.*?\n        uses: actions/checkout@[^\n]+\n(.*?)(?=^      - name:|^  [a-zA-Z_-]+:|\Z)", source):
                self.assertIn("persist-credentials: false", checkout, name)

    def test_dispatch_workflows_require_enabled_main_and_authorized_actor(self):
        for name in ("candidate", "validate", "decide", "heartbeat", "attest"):
            source = workflow(name)
            self.assertIn("workflow_dispatch:", source, name)
            self.assertIn("vars.MAINTENANCE_ENABLED == 'true'", source, name)
            self.assertIn("github.ref == 'refs/heads/main'", source, name)
            actor = "MAINTENANCE_HOST_ATTESTOR_LOGIN" if name == "attest" else "MAINTENANCE_APP_LOGIN"
            self.assertIn(f"github.actor == vars.{actor}", source, name)

    def test_privileged_jobs_use_trusted_checkout_and_never_candidate_checkout(self):
        for file_name, job_name in (("candidate", "publish"), ("decide", "decide")):
            block = job_block(workflow(file_name), job_name)
            self.assertIn("ref: ${{ github.sha }}", block)
            self.assertIn("path: trusted", block)
            self.assertIn("persist-credentials: false", block)
            self.assertNotIn("path: candidate", block)
            self.assertNotIn("inputs.head", block)
            self.assertIn("actions/create-github-app-token@", block)
        publish = job_block(workflow("candidate"), "publish")
        self.assertIn("permission-contents: write", publish)
        self.assertIn("permission-pull-requests: write", publish)
        self.assertIn("permission-actions: write", publish)

    def test_candidate_is_generated_secretless_and_published_from_artifact(self):
        source = workflow("candidate")
        generate = job_block(source, "generate")
        publish = job_block(source, "publish")
        self.assertIn("ref: ${{ github.sha }}", generate)
        self.assertIn("ref: ${{ inputs.base }}", generate)
        self.assertNotIn("secrets.", generate)
        self.assertIn("inputs.base == github.sha", generate)
        self.assertIn("name: maintenance-candidate-files", generate)
        self.assertIn("name: maintenance-candidate-files", publish)
        self.assertIn("--bundle bundle/evidence.json", publish)
        self.assertIn("M_BASE: ${{ inputs.base }}", publish)

    def test_native_matrix_is_trusted_and_complete(self):
        source = workflow("validate")
        self.assertIn("ubuntu-24.04", source)
        self.assertIn("ubuntu-24.04-arm", source)
        self.assertIn("macos-14", source)
        for system in ("x86_64-linux", "aarch64-linux", "aarch64-darwin"):
            self.assertIn(f"system: {system}", source)
            self.assertIn(f"name: native-${{{{ matrix.system }}}}", source)
        native = job_block(source, "native")
        self.assertIn("ref: ${{ github.sha }}", native)
        self.assertIn("ref: ${{ inputs.head }}", native)
        self.assertIn("persist-credentials: false", native)
        self.assertIn("sandbox = true", native)
        self.assertIn("--identity identity/evidence.json", native)

    def test_aggregate_status_fails_closed_on_missing_or_failed_shards(self):
        source = workflow("validate")
        aggregate = job_block(source, "aggregate")
        self.assertIn("if: always()", aggregate)
        self.assertIn("pattern: native-*", aggregate)
        self.assertIn("merge-multiple: false", aggregate)
        self.assertIn("maintenance.cli collect", aggregate)
        self.assertIn("statuses: write", aggregate)
        self.assertIn('"context": "Maintenance / native evidence"', aggregate)
        self.assertIn('"state": os.environ["STATUS_STATE"]', aggregate)
        self.assertIn("'failure'", aggregate)
        self.assertIn("Require successful native collection", aggregate)
        self.assertNotIn("statuses: write", source.split("  native:", 1)[1].split("  aggregate:", 1)[0])

    def test_merge_is_doubly_opted_in_and_policy_remains_disabled(self):
        source = workflow("decide")
        self.assertIn("vars.MAINTENANCE_AUTOMERGE == 'true'", source)
        self.assertIn("environment: maintenance-merge", source)
        self.assertIn("maintenance.cli decide", source)
        policy = (ROOT / "maintenance" / "policy.json").read_text(encoding="utf-8")
        self.assertRegex(policy, r'"merge_enabled"\s*:\s*false')

    def test_privileged_api_permissions_cover_evidence_and_pr_reads(self):
        decide = job_block(workflow("decide"), "decide")
        self.assertIn("permission-actions: read", decide)
        validate_prepare = job_block(workflow("validate"), "prepare")
        attest_prepare = job_block(workflow("attest"), "prepare")
        self.assertIn("pull-requests: read", validate_prepare)
        self.assertIn("pull-requests: read", attest_prepare)

    def test_heartbeat_watchdog_and_host_attestation_are_bounded(self):
        heartbeat = workflow("heartbeat")
        self.assertNotIn("checkout@", heartbeat)
        watchdog = workflow("watchdog")
        self.assertIn("cron: '43 */6 * * *'", watchdog)
        self.assertIn("maintenance.cli watchdog", watchdog)
        notify = job_block(watchdog, "notify-owner")
        self.assertIn("actions/cache/restore@0057852bfaa89a56745cba8c7296529d2fc39830", notify)
        self.assertIn("actions/cache/save@0057852bfaa89a56745cba8c7296529d2fc39830", notify)
        self.assertIn("group: maintenance-watchdog-notify", notify)
        self.assertIn("cancel-in-progress: false", notify)
        self.assertIn("if: needs.watchdog.result == 'failure'", notify)
        self.assertIn('"fingerprint": "watchdog:heartbeat"', notify)
        self.assertIn("maintenance.notify enqueue", notify)
        self.assertIn("from maintenance.notify import deliver", notify)
        self.assertIn('if result["retried"] or result["blocked"]:', notify)
        self.assertIn("maintenance-watchdog-v1-main-", notify)
        self.assertIn("MAINTENANCE_TELEGRAM_BOT_TOKEN", notify)
        self.assertIn("MAINTENANCE_TELEGRAM_OWNER_ID", notify)
        self.assertNotIn("MAINTENANCE_APP_PRIVATE_KEY", notify)

        attest = workflow("attest")
        self.assertIn("maintenance.cli prepare", attest)
        self.assertIn("maintenance.cli accept-attestation", attest)
        self.assertIn("--identity identity/evidence.json", attest)
        self.assertIn("--attestation supplied/evidence.json", attest)
        self.assertIn("name: maintenance-host-attestation", attest)
        self.assertNotIn("candidate", job_block(attest, "accept"))

    def test_no_openai_credentials_or_candidate_secrets_are_in_workflows(self):
        for name in FILES:
            source = workflow(name)
            self.assertNotRegex(source, r"secrets\.[A-Za-z0-9_]*(?:OPENAI|API_KEY)")
        for name in ("candidate", "validate", "decide", "attest"):
            source = workflow(name)
            self.assertNotIn("path: candidate\n          persist-credentials: true", source)


if __name__ == "__main__":
    unittest.main()
