"""Static safety checks for the dormant Thorny maintenance service module."""
from pathlib import Path
import unittest


MODULE = Path(__file__).parents[1] / "flakes/hosts/thorny/maintenance.nix"
TEXT = MODULE.read_text()


class MaintenanceServiceTests(unittest.TestCase):
    def test_module_is_opt_in_and_credentials_are_mandatory_when_enabled(self):
        self.assertRegex(TEXT, r'enable\s*=\s*lib\.mkEnableOption')
        self.assertRegex(TEXT, r'appLogin\s*=\s*lib\.mkOption\s*\{[^}]*default\s*=\s*""')
        self.assertRegex(TEXT, r'githubAppKeyFile\s*=\s*lib\.mkOption\s*\{[^}]*default\s*=\s*null')
        self.assertRegex(TEXT, r'openaiApiKeyFile\s*=\s*lib\.mkOption\s*\{[^}]*default\s*=\s*null')
        self.assertIn("(lib.mkIf cfg.enable", TEXT)
        self.assertIn("githubAppKeyFile != null", TEXT)
        self.assertIn("openaiApiKeyFile != null", TEXT)
        self.assertIn('lib.hasSuffix "[bot]" cfg.appLogin', TEXT)

    def test_controller_and_notifier_receive_separate_credentials(self):
        controller = TEXT.split("systemd.services.dotfiles-maintenance = {", 1)[1].split(
            "systemd.timers.dotfiles-maintenance =", 1)[0]
        notifier = TEXT.split("systemd.services.dotfiles-maintenance-notify = {", 1)[1].split(
            "systemd.timers.dotfiles-maintenance-notify =", 1)[0]
        self.assertIn('"github-app-key:${toString cfg.githubAppKeyFile}"', controller)
        self.assertIn('"openai-api-key:${toString cfg.openaiApiKeyFile}"', controller)
        self.assertNotIn("bot-token", controller)
        self.assertNotIn("owner-id", controller)
        self.assertNotIn("openai-api-key", notifier)
        self.assertIn('"bot-token:${toString cfg.telegramBotTokenFile}"', notifier)
        self.assertIn('"owner-id:${toString cfg.telegramOwnerIdFile}"', notifier)
        self.assertNotIn("GH_TOKEN", TEXT)
        self.assertIn("pkgs.openssl", controller)

    def test_services_are_hardened_and_state_access_is_scoped(self):
        for attr in ("NoNewPrivileges", "PrivateUsers", "PrivateTmp", "PrivateDevices",
                     "ProtectSystem", "ProtectHome", "CapabilityBoundingSet", "ReadWritePaths",
                     "RestrictAddressFamilies"):
            self.assertIn(f"{attr} =", TEXT)
        self.assertIn('ReadWritePaths = [stateDir requestDir]', TEXT)
        self.assertIn('ReadWritePaths = [stateDir]', TEXT)
        self.assertIn('"d ${requestDir} 2770 root dotfiles-maintenance-requests -"', TEXT)
        self.assertIn('users.users.zeroclaw-home.extraGroups = ["dotfiles-maintenance-requests"]', TEXT)

    def test_python_package_layout_and_separate_fixed_cli_wrappers(self):
        self.assertIn('mkdir -p "$out/maintenance"', TEXT)
        self.assertIn('cp -R ${source}/. "$out/maintenance/"', TEXT)
        self.assertIn('name = "michi-maintenance"', TEXT)
        self.assertIn('${maintenanceRuntime}/maintenance/cli.py request', TEXT)
        self.assertIn('--requests ${requestDir} "$@"', TEXT)
        self.assertIn('name = "dotfiles-maintenance-controller"', TEXT)
        self.assertIn('${maintenanceRuntime}/maintenance/cli.py "$@"', TEXT)
        self.assertNotIn("PYTHONPATH:+", TEXT)
        self.assertIn('lib.getExe controllerPackage', TEXT)
        self.assertIn('lib.escapeShellArgs [', TEXT)
        self.assertIn('TimeoutStartSec = "15min"', TEXT)
        self.assertIn('TimeoutStartSec = "2min"', TEXT)
        self.assertIn('PathChanged = "${requestDir}/request.json"', TEXT)
        self.assertIn("--requests ${requestDir}", TEXT)

    def test_periodic_units_are_opt_in_and_use_expected_intervals(self):
        self.assertIn('OnUnitActiveSec = "15m"', TEXT)
        self.assertIn('OnUnitActiveSec = "30s"', TEXT)
        # Both timers and both services are declared inside the enable-only block.
        enable_block = TEXT.split("(lib.mkIf cfg.enable", 1)[1]
        self.assertIn("systemd.timers.dotfiles-maintenance =", enable_block)
        self.assertIn("systemd.timers.dotfiles-maintenance-notify =", enable_block)


if __name__ == "__main__":
    unittest.main()
