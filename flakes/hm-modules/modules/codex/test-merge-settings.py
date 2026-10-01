import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

import tomlkit

spec = importlib.util.spec_from_file_location("merge_settings", Path(__file__).with_name("merge-settings.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class MergeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.config = self.directory / "config.toml"

    def test_desktop_settings_survive_add_update_and_removal(self):
        original = '# Desktop preferences\n[desktop]\nfollowUpQueueMode = "steer"\n[mcp_servers.browser]\ncommand = "/app/browser"\n'
        self.config.write_text(original)
        module.merge(self.directory, {"model_reasoning_effort": "medium", "mcp_servers": {"extra": {"url": "https://example.com"}}})
        first = self.config.read_text()
        module.merge(self.directory, {"model_reasoning_effort": "medium", "mcp_servers": {"extra": {"url": "https://example.com"}}})
        self.assertEqual(first, self.config.read_text())
        self.assertIn("# Desktop preferences", first)
        # A local change to a removed declaration must survive.
        self.config.write_text(first.replace('model_reasoning_effort = "medium"', 'model_reasoning_effort = "high"'))
        module.merge(self.directory, {})
        parsed = tomlkit.parse(self.config.read_text())
        self.assertEqual(parsed["model_reasoning_effort"], "high")
        self.assertEqual(parsed["desktop"]["followUpQueueMode"], "steer")
        self.assertEqual(parsed["mcp_servers"]["browser"]["command"], "/app/browser")
        self.assertNotIn("extra", parsed["mcp_servers"])
        self.assertEqual((self.directory / "config.toml.before-dotfiles").read_text(), original)
        self.assertEqual(self.config.stat().st_mode & 0o777, 0o600)

    def test_current_declarations_override_local_edits(self):
        module.merge(self.directory, {"model": "original"})
        self.config.write_text('model = "local"\n')
        module.merge(self.directory, {"model": "declared"})
        self.assertEqual(tomlkit.parse(self.config.read_text())["model"], "declared")

    def test_empty_settings_do_not_create_configuration(self):
        module.merge(self.directory / "absent", {})
        self.assertFalse((self.directory / "absent").exists())

    def test_invalid_config_and_scalar_table_collision_do_not_write(self):
        for original in ['[bad', 'mcp_servers = "scalar"\n']:
            self.config.write_text(original)
            with self.assertRaises(Exception):
                module.merge(self.directory, {"mcp_servers": {"extra": {"url": "x"}}})
            self.assertEqual(self.config.read_text(), original)
            self.assertFalse((self.directory / "dotfiles-managed-settings.json").exists())

    def test_symlink_is_not_replaced(self):
        target = self.directory / "immutable.toml"
        target.write_text('model = "original"\n')
        self.config.symlink_to(target)
        with self.assertRaises(ValueError):
            module.merge(self.directory, {"model": "new"})
        self.assertTrue(self.config.is_symlink())
        self.assertEqual(target.read_text(), 'model = "original"\n')

    def test_removed_parent_preserves_unmanaged_sibling(self):
        module.merge(self.directory, {"mcp_servers": {"extra": {"url": "x"}}})
        document = tomlkit.parse(self.config.read_text())
        document["mcp_servers"]["extra"]["enabled"] = False
        self.config.write_text(tomlkit.dumps(document))
        module.merge(self.directory, {})
        self.assertEqual(tomlkit.parse(self.config.read_text())["mcp_servers"]["extra"], {"enabled": False})


if __name__ == "__main__":
    unittest.main()
