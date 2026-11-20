import hashlib
import importlib.util
import re
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("morrowind", Path(__file__).with_name("morrowind-setup.py"))
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class SetupTests(unittest.TestCase):
    def setUp(self):
        home = Path(self.enterContext(tempfile.TemporaryDirectory())).resolve()
        openmw_home = home / "openmw"
        self.mods = openmw_home / "mods"
        self.downloads = openmw_home / "downloads"
        self.mods.mkdir(parents=True)
        self.downloads.mkdir()
        self.config = home / "config/tr/openmw"
        self.cfg = self.config / "openmw.cfg"
        self.game = home / ".local/share/Steam/steamapps/common/Morrowind"
        self.game_data = self.game / "Data Files"
        self.save_dir = home / "data/tr/openmw/saves"
        self.enterContext(patch.multiple(
            setup, HOME=home, OPENMW_HOME=openmw_home, MODS=self.mods, DOWNLOADS=self.downloads,
            PROFILE_ROOTS={
                "tr": (self.config.parent, self.save_dir.parent.parent),
                "rebirth": (home / "config/rebirth", home / "data/rebirth"),
            },
            CONFIG=self.config, CFG=self.cfg,
        ))
        self.enterContext(patch.object(setup, "say"))
        self.enterContext(patch.object(setup, "import_game_fallbacks", return_value=[
            "fallback-archive=Morrowind.bsa", "fallback-archive=Tribunal.bsa",
            "fallback-archive=Bloodmoon.bsa", "fallback=Example_First,default",
            "fallback=Example_Second,imported",
        ]))

    @staticmethod
    def write_files(root, *files):
        for name in files:
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture")

    def stage_files(self, mod, *files):
        self.write_files(self.mods / mod, ".morrowind-setup-ready", *files)

    def stage_tr(self):
        self.stage_files("Tamriel Rebuilt", "TR_Mainland.esm", "tamrielrebuilt.omwscripts", "TR_Factions.esp")
        self.stage_files("Tamriel Data HD", "Tamriel_Data.esm", "Tamriel_Data.omwscripts")
        self.write_files(self.game, "Morrowind.ini")
        self.write_files(self.game_data, "Morrowind.esm", "Tribunal.esm", "Bloodmoon.esm")

    def archive(self, filename, *entries):
        archive = self.downloads / filename
        with zipfile.ZipFile(archive, "w") as zipped:
            for entry in entries:
                zipped.writestr(entry, "asset")
        return archive

    @staticmethod
    def extract_stub(args, *, check):
        destination = next(arg[2:] for arg in args if arg.startswith("-o"))
        with zipfile.ZipFile(args[-1]) as archive:
            archive.extractall(destination)

    def test_failed_layout_preserves_cache_and_correct_archive_recovers(self):
        self.stage_files("MET", "unexpected/textures/asset.dds")
        destination = self.mods / "MET"
        pattern = re.compile(r"met-.*\.zip$")
        malformed = self.archive("met-invalid.zip", "unexpected/textures/other.dds")
        with patch.object(setup.subprocess, "run", side_effect=self.extract_stub):
            with self.assertRaisesRegex(setup.SetupError, "invalid or ambiguous layout"):
                setup.stage(pattern, destination, hashlib.sha256(malformed.read_bytes()).hexdigest(), trees=("expected/textures",))
            self.assertTrue((destination / "unexpected/textures/asset.dds").is_file())
            good = self.archive("met-good.zip", "expected/textures/asset.dds")
            self.archive("met-newer.zip", "expected/textures/wrong-version.dds")
            self.assertEqual(setup.stage(
                pattern, destination, hashlib.sha256(good.read_bytes()).hexdigest(), trees=("expected/textures",),
            ), destination)
        self.assertTrue((destination / "expected/textures/asset.dds").is_file())
        self.assertTrue(any(self.mods.glob("MET.previous-*/unexpected/textures/asset.dds")))

    def test_first_cli_run_creates_shared_dirs_and_can_extract(self):
        archive = self.archive("Morrowind Enhanced Textures 6.1.zip", "MET 6-1 main/textures/example.dds")
        home_downloads = setup.HOME / "Downloads"
        home_downloads.mkdir()
        archive = archive.rename(home_downloads / archive.name)
        self.mods.rmdir()
        self.downloads.rmdir()
        stage = setup.stage

        def stage_fixture(pattern, destination, checksum, **kwargs):
            if destination.name == "Morrowind Enhanced Textures":
                checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
            return stage(pattern, destination, checksum, **kwargs)

        with (
            patch.object(sys, "argv", ["morrowind-setup", "--stage-only"]),
            patch.object(setup, "stage", side_effect=stage_fixture),
            patch.object(setup.subprocess, "run", side_effect=self.extract_stub),
        ):
            # Only MET is present. The next required archive should stop setup.
            self.assertEqual(setup.main(), 1)
        self.assertTrue((self.mods / "Morrowind Enhanced Textures/MET 6-1 main/textures/example.dds").is_file())
        self.assertTrue(self.downloads.is_dir())

    def test_tr_stage_only_rejects_duplicate_plugin(self):
        self.stage_tr()
        self.stage_files("Patch for Purists", "one/Patch for Purists.esm", "two/Patch for Purists.esm")
        with self.assertRaisesRegex(setup.SetupError, "Patch for Purists"):
            setup.setup_tr(stage_only=True)
        self.assertFalse(self.cfg.exists())

    def test_tr_rerun_restores_order_and_keeps_saves_and_custom_config(self):
        self.stage_tr()
        self.assertEqual(setup.setup_tr(), 0)
        self.write_files(self.mods / "Patch for Purists", "Patch for Purists.esm")
        self.write_files(self.save_dir, "existing.omwsave")
        custom_assets = self.mods / "Tamriel Rebuilt/custom-textures"
        self.write_files(custom_assets, "texture.dds")
        launcher = self.config / "launcher.cfg"
        launcher.write_text("[General]\nfirstrun=true\n")
        with self.cfg.open("a") as config:
            config.write(f'data="{custom_assets}"\ncontent=TR_Factions.esp\n')
        original = self.cfg.read_text().replace("fallback-archive=Tribunal.bsa\n", "").replace(
            "fallback=Example_First,default", "fallback=Example_First,custom",
        ).replace("fallback=Example_Second,imported\n", "")
        self.cfg.write_text(original)
        self.assertEqual(setup.setup_tr(), 0)
        updated = self.cfg.read_text()
        self.assertLess(updated.index("Patch for Purists\""), updated.index("Tamriel Data HD\""))
        self.assertLess(updated.index("Tamriel Rebuilt\""), updated.index("custom-textures\""))
        for fragment in (
            "content=TR_Factions.esp", "fallback-archive=Tribunal.bsa",
            "fallback=Example_First,custom", "fallback=Example_Second,imported",
        ):
            self.assertIn(fragment, updated)
        self.assertTrue(any(path.read_text() == original for path in self.config.glob("openmw.cfg.bak-*")))
        self.assertEqual(launcher.read_text(), "[General]\nfirstrun=true\n")
        self.assertEqual((self.save_dir / "existing.omwsave").read_text(), "fixture")
        self.assertEqual(setup.setup_tr(), 0)
        self.assertEqual(self.cfg.read_text(), updated)

    def test_repair_leaves_configured_custom_assets_in_place(self):
        self.stage_tr()
        self.assertEqual(setup.setup_tr(), 0)
        destination = self.mods / "Tamriel Rebuilt"
        custom_assets = destination / "custom-textures"
        self.write_files(custom_assets, "texture.dds")
        original = self.cfg.read_text() + f'data="{custom_assets}"\n'
        self.cfg.write_text(original)
        (destination / "TR_Mainland.esm").unlink()
        archive = self.archive("Tamriel_Rebuilt_26.08a.7z", "TR_Mainland.esm", "tamrielrebuilt.omwscripts")
        stage = setup.stage

        def stage_fixture(pattern, target, checksum, **kwargs):
            if target == destination:
                checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
            return stage(pattern, target, checksum, **kwargs)

        with (
            patch.object(setup, "stage", side_effect=stage_fixture),
            patch.object(setup.subprocess, "run", side_effect=self.extract_stub),
        ):
            for stage_only in (False, True):
                with self.subTest(stage_only=stage_only):
                    with self.assertRaisesRegex(setup.SetupError, "would remove configured data directory"):
                        setup.setup_tr(stage_only=stage_only)
                    self.assertEqual((custom_assets / "texture.dds").read_text(), "fixture")
                    self.assertEqual(self.cfg.read_text(), original)
                    self.assertFalse(any(self.mods.glob("Tamriel Rebuilt.previous-*")))

    def test_unknown_plugin_leaves_existing_config_in_place(self):
        self.stage_tr()
        self.config.mkdir(parents=True)
        original = "content=Unmanaged.esp\n"
        self.cfg.write_text(original)
        self.assertEqual(setup.setup_tr(), 1)
        self.assertEqual(self.cfg.read_text(), original)

    def test_profiles_have_separate_config_and_data(self):
        self.stage_tr()
        self.assertEqual(setup.setup_tr(), 0)
        tr_config = self.cfg.read_text()
        self.stage_files("Morrowind Enhanced Textures", "MET 6-1 main/textures/fixture.dds")
        self.stage_files(
            "Morrowind Rebirth",
            "Data Files/Morrowind Rebirth [Main].ESP",
            "Compability Patches/Morrowind Patch Project v1.6.6 [For Rebirth].esm",
            *(f"Data Files/Morrowind Rebirth - {addon} [Addon].{extension}" for addon, extension in (
                ("Birthsigns", "ESP"), ("Game Settings", "ESP"), ("Mercenaries", "ESP"),
                ("Races", "esp"), ("Skills", "ESP"), ("Tools", "ESP"),
            )),
        )
        self.stage_files("Familiar Faces", "Meshes/fixture.nif")
        self.stage_files("Graphic Herbalism", "00 Core + Vanilla Meshes/fixture.nif")
        self.stage_files(
            "Glow in the Dahrk",
            "00 Core/fixture.nif",
            "01 Hi Res Window Texture Replacer/fixture.dds",
            "03 Nord Glass Windows/fixture.nif",
            "05 Raven Rock Glass Windows/GITD_WL_RR_Interiors.esp",
        )
        rebirth = self.config.parent.parent / "rebirth/openmw"
        rebirth_data = self.save_dir.parent.parent.parent / "rebirth"
        with patch.multiple(setup, CONFIG=rebirth, CFG=rebirth / "openmw.cfg"):
            with patch.dict(setup.PROFILE_ROOTS, rebirth=(rebirth.parent, rebirth_data)):
                self.assertEqual(setup.setup_rebirth(stage_only=True), 0)
                self.assertFalse(setup.CFG.exists())
                self.assertEqual(setup.setup_rebirth(), 0)
                config = setup.CFG.read_text()
                (self.mods / "Glow in the Dahrk/00 Core/fixture.nif").unlink()
                with self.assertRaisesRegex(setup.SetupError, "Glow in the Dahrk"):
                    setup.setup_rebirth(stage_only=True)
                self.assertEqual(setup.CFG.read_text(), config)
        self.assertLess(config.index("MET 6-1 main"), config.index("Morrowind Rebirth/Data Files"))
        self.assertIn(f'user-data="{rebirth_data / "openmw"}"', config)
        self.assertNotIn("Tamriel Rebuilt", config)
        self.assertEqual(self.cfg.read_text(), tr_config)


if __name__ == "__main__":
    unittest.main()
