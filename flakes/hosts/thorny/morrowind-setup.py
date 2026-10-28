#!/usr/bin/env python3
"""Set up isolated Rebirth and Tamriel Rebuilt profiles for OpenMW."""

import argparse
import os
import re
import shutil
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path


HOME = Path.home()
DATA_HOME = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share"))
CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config"))
# Mods and downloads are intentionally shared. Only OpenMW configuration and
# user data (including saves) live under per-profile roots.
OPENMW_HOME = DATA_HOME / "openmw"
DOWNLOADS = OPENMW_HOME / "downloads"
MODS = OPENMW_HOME / "mods"
PROFILE_ROOTS = {
    "rebirth": (CONFIG_HOME / "morrowind/rebirth", DATA_HOME / "morrowind/rebirth"),
    "tr": (CONFIG_HOME / "morrowind/tr", DATA_HOME / "morrowind/tr"),
}
CONFIG = None
CFG = None


def say(message):
    print(message)


def find_files(root, filename):
    wanted = filename.casefold()
    return sorted((path for path in root.rglob("*") if path.is_file() and path.name.casefold() == wanted), key=str)


def find_archives(pattern):
    candidates = []
    for root in (DOWNLOADS, HOME / "Downloads"):
        if root.is_dir():
            candidates.extend(path for path in root.rglob("*") if path.is_file() and pattern.search(path.name))
    return sorted(set(candidates), key=lambda path: (path.stat().st_mtime_ns, str(path)), reverse=True)


def has_files(root, expected):
    if not root.is_dir():
        return False
    if isinstance(expected, str):
        expected = (expected,)
    found = {
        path.name.casefold()
        for path in root.rglob("*")
        if path.is_dir() or (path.is_file() and path.stat().st_size > 0)
    }
    groups = expected if expected and isinstance(expected[0], tuple) else (expected,)
    return any(all(name.casefold() in found for name in group) for group in groups)


def extract_archive(archive, destination, expected):
    with tempfile.TemporaryDirectory(prefix=f".{destination.name}.extract-", dir=MODS) as temp_name:
        temp = Path(temp_name)
        say(f"Extracting {archive.name} to {destination}")
        if archive.suffix.casefold() == ".rar":
            subprocess.run(["unrar", "x", "-o+", "-idq", str(archive), f"{temp}/"], check=True)
        else:
            subprocess.run(["7zz", "x", "-y", f"-o{temp}", str(archive)], check=True)
        if not has_files(temp, expected):
            groups = (expected,) if isinstance(expected, str) else expected
            names = [name for group in groups for name in (group if isinstance(group, tuple) else (group,))]
            say(f"Archive did not contain the expected files {', '.join(names)}; {destination} was left unchanged.")
            return False
        (temp / ".morrowind-setup-ready").touch()
        if destination.exists():
            stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
            backup = destination.with_name(f"{destination.name}.previous-{stamp}")
            os.replace(destination, backup)
            say(f"Moved incomplete prior extraction to {backup}")
        os.replace(temp, destination)
    return True


def stage(pattern, destination, expected, required=False):
    if (destination / ".morrowind-setup-ready").is_file() and has_files(destination, expected):
        say(f"Already extracted: {destination}")
        return True
    archives = find_archives(pattern)
    archive = archives[0] if archives else None
    if archive is None:
        if required:
            say(f"Missing archive matching {pattern.pattern!r} in {DOWNLOADS} or ~/Downloads")
        return not required
    if len(archives) > 1:
        say(f"Found {len(archives)} matching archives; using newest: {archive}")
    return extract_archive(archive, destination, expected)


def steam_libraries():
    roots = [
        HOME / ".local/share/Steam",
        HOME / ".steam/steam",
        HOME / ".steam/root",
        HOME / ".steam/debian-installation",
    ]
    libraries = list(roots)
    seen = set()
    for root in roots:
        vdf = root / "steamapps/libraryfolders.vdf"
        if not vdf.is_file():
            continue
        for raw_path in re.findall(r'"path"\s+"((?:\\.|[^"])*)"', vdf.read_text(errors="replace")):
            decoded = raw_path.replace("\\\\", "\\").replace('\\"', '"')
            libraries.append(Path(decoded).expanduser())
    result = []
    for library in libraries:
        library = library.resolve()
        if library not in seen:
            seen.add(library)
            result.append(library)
    return result


def find_game():
    for library in steam_libraries():
        common = library / "steamapps/common"
        if not common.is_dir():
            continue
        for entry in common.iterdir():
            if entry.is_dir() and entry.name.casefold() == "morrowind":
                masters = {p.name.casefold() for p in find_files(entry, "Morrowind.esm")}
                ini = find_files(entry, "Morrowind.ini")
                if "morrowind.esm" in masters and ini:
                    data_files = next(iter(find_files(entry, "Morrowind.esm"))).parent
                    if all((data_files / name).is_file() for name in ("Tribunal.esm", "Bloodmoon.esm")):
                        return entry, data_files, ini[0]
    return None


def mod_data_dirs(mod_root, plugin):
    matches = find_files(mod_root, plugin)
    if len(matches) != 1:
        return [], matches
    return [matches[0].parent], matches


def existing_content():
    if not CFG.is_file():
        return []
    return [
        value.strip().strip('"').casefold()
        for line in CFG.read_text(errors="replace").splitlines()
        if (match := re.match(r"\s*content\s*=\s*(.*?)\s*$", line, re.IGNORECASE))
        for value in [match.group(1)]
        if value and not value.startswith("#")
    ]


def refuse_unknown_content(profile, allowed_plugins):
    allowed = {name.casefold() for name in allowed_plugins}
    unknown = sorted(set(existing_content()) - allowed)
    if not unknown:
        return False
    say(f"Existing {profile} OpenMW config has content entries this setup would replace:")
    for plugin in unknown:
        say(f"  {plugin}")
    say(f"Remove or back up those entries yourself, then run morrowind-setup --profile {profile.lower()} again.")
    return True


def import_game_fallbacks(game_data, ini):
    with tempfile.TemporaryDirectory(prefix="morrowind-setup-") as temp_name:
        temp = Path(temp_name)
        base_cfg = temp / "base.cfg"
        imported_cfg = temp / "imported.cfg"
        base_cfg.write_text(f'data="{game_data}"\n')
        subprocess.run(
            ["openmw-iniimporter", "--ini", str(ini), "--cfg", str(base_cfg), "--output", str(imported_cfg), "--game-files"],
            check=True,
        )
        if not imported_cfg.is_file():
            say("openmw-iniimporter did not produce its temporary config; no user config was changed.")
            return None
        return [
            line for line in imported_cfg.read_text(errors="replace").splitlines()
            if line.strip().lower().startswith(("fallback=", "fallback-archive="))
        ]


def write_profile_config(profile, data_dirs, ordered_plugins, fallbacks):
    existing_lines = CFG.read_text(errors="replace").splitlines() if CFG.exists() else []
    preserved_lines = [
        line for line in existing_lines
        if not re.match(r"\s*(?:content|user-data|data-local)\s*=", line, re.IGNORECASE)
        and line.strip() != "# Generated by morrowind-setup; OpenMW Launcher may edit this file."
    ]
    existing_keys = {
        match.group(1).strip().casefold()
        for line in preserved_lines
        if (match := re.match(r"\s*([^#=]+?)\s*=", line))
    }
    preserved_data = {
        match.group(1).strip().strip('"').casefold()
        for line in preserved_lines
        if (match := re.match(r"\s*data\s*=\s*(.*?)\s*$", line, re.IGNORECASE))
    }
    unique_data_dirs = list(dict.fromkeys(path.resolve() for path in data_dirs))
    lines = ["# Generated by morrowind-setup; OpenMW Launcher may edit this file.", *preserved_lines]
    lines.extend(
        f'data="{path}"' for path in unique_data_dirs
        if str(path).casefold() not in preserved_data
    )
    lines.extend(f"content={plugin}" for plugin in ordered_plugins)
    profile_data = PROFILE_ROOTS[profile][1] / "openmw"
    profile_data.mkdir(parents=True, exist_ok=True)
    (profile_data / "data").mkdir(parents=True, exist_ok=True)
    lines.append(f'user-data="{profile_data}"')
    lines.append(f'data-local="{profile_data / "data"}"')
    lines.extend(
        line for line in fallbacks
        if line.split("=", 1)[0].strip().casefold() not in existing_keys
    )

    CONFIG.mkdir(parents=True, exist_ok=True)
    if CFG.exists():
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
        backup = CFG.with_name(f"openmw.cfg.bak-{stamp}")
        shutil.copy2(CFG, backup)
        say(f"Backed up existing config to {backup}")
    temp_cfg = CFG.with_suffix(".cfg.tmp")
    temp_cfg.write_text("\n".join(lines) + "\n")
    os.replace(temp_cfg, CFG)
    launcher_cfg = CONFIG / "launcher.cfg"
    if not launcher_cfg.exists():
        launcher_cfg.write_text("[General]\nfirstrun=false\n")
    say(f"OpenMW {profile} config written: {CFG}")
    say("Enabled content: " + ", ".join(ordered_plugins))


def setup_tr(stage_only=False):
    MODS.mkdir(parents=True, exist_ok=True)
    DOWNLOADS.mkdir(parents=True, exist_ok=True)

    required_archives = [
        stage(re.compile(r"tamriel[_ -]?rebuilt.*\.7z$", re.IGNORECASE), MODS / "Tamriel Rebuilt", ("TR_Mainland.esm", "tamrielrebuilt.omwscripts"), True),
        stage(re.compile(r"tamriel[_ -]?data.*26\.08.*hd.*\.7z$", re.IGNORECASE), MODS / "Tamriel Data HD", ("Tamriel_Data.esm", "Tamriel_Data.omwscripts"), True),
    ]
    if not all(required_archives):
        return 1

    pfp_staged = stage(
        re.compile(r"patch[_ -]+for[_ -]+purists.*\.(?:7z|zip)$", re.IGNORECASE),
        MODS / "Patch for Purists",
        (("Patch for Purists.esm",), ("Patch for Purists.esp",)),
    )
    delay_staged = stage(
        re.compile(r"expansion[_ -]+delay.*\.(?:7z|zip)$", re.IGNORECASE),
        MODS / "Expansion Delay",
        (("Expansion Delay.ESP",), ("Expansion Delay.esp",)),
    )
    mop_staged = stage(
        re.compile(r"morrowind[_ -]+optimization[_ -]+patch.*\.(?:7z|zip)$", re.IGNORECASE),
        MODS / "Morrowind Optimization Patch",
        ("Meshes",),
    )

    if stage_only:
        say("TR profile archives staged; Steam game discovery was skipped.")
        return 0

    tr_root = MODS / "Tamriel Rebuilt"
    td_root = MODS / "Tamriel Data HD"
    tr_dirs, tr_plugins = mod_data_dirs(tr_root, "TR_Mainland.esm")
    td_dirs, td_plugins = mod_data_dirs(td_root, "Tamriel_Data.esm")
    tr_scripts = find_files(tr_root, "tamrielrebuilt.omwscripts")
    td_scripts = find_files(td_root, "Tamriel_Data.omwscripts")
    if len(tr_plugins) != 1 or len(tr_scripts) != 1:
        say(f"Expected one TR_Mainland.esm and tamrielrebuilt.omwscripts under {tr_root}")
        return 1
    if len(td_plugins) != 1 or len(td_scripts) != 1:
        say(f"Expected one Tamriel_Data.esm and Tamriel_Data.omwscripts in the HD archive under {td_root}")
        return 1

    game = find_game()
    if game is None:
        say("Morrowind, Tribunal, Bloodmoon, and Morrowind.ini were not found in Steam libraries.")
        say("Install Morrowind in Steam, then run morrowind-setup again.")
        return 1
    game_root, game_data, ini = game

    pfp_root = MODS / "Patch for Purists"
    pfp_dirs, pfp_plugins = mod_data_dirs(pfp_root, "Patch for Purists.esm") if pfp_staged and pfp_root.exists() else ([], [])
    if not pfp_plugins and pfp_staged and pfp_root.exists():
        pfp_dirs, pfp_plugins = mod_data_dirs(pfp_root, "Patch for Purists.esp")
    delay_root = MODS / "Expansion Delay"
    delay_dirs, delay_plugins = mod_data_dirs(delay_root, "Expansion Delay.ESP") if delay_staged and delay_root.exists() else ([], [])
    if not delay_plugins and delay_staged and delay_root.exists():
        delay_dirs, delay_plugins = mod_data_dirs(delay_root, "Expansion Delay.esp")
    pfp_plugin = pfp_plugins[0].name if pfp_plugins else None
    delay_plugin = delay_plugins[0].name if delay_plugins else None

    ordered_plugins = ["Morrowind.esm", "Tribunal.esm", "Bloodmoon.esm"]
    if pfp_plugin:
        ordered_plugins.append(pfp_plugin)
    ordered_plugins.extend([
        "Tamriel_Data.esm",
        "Tamriel_Data.omwscripts",
        "TR_Mainland.esm",
        "tamrielrebuilt.omwscripts",
    ])
    if delay_plugin:
        ordered_plugins.append(delay_plugin)

    if refuse_unknown_content("TR", ordered_plugins):
        return 1

    fallbacks = import_game_fallbacks(game_data, ini)
    if fallbacks is None:
        return 1

    mop_root = MODS / "Morrowind Optimization Patch"
    mop_core = next(
        (path for path in mop_root.rglob("*") if path.is_dir() and path.name.casefold() == "00 core"),
        None,
    ) if mop_staged else None
    data_dirs = [game_data, *pfp_dirs, *td_dirs, *tr_dirs, *delay_dirs]
    if mop_core:
        data_dirs.append(mop_core)
    write_profile_config("tr", data_dirs, ordered_plugins, fallbacks)
    say(f"Game files: {game_root}")
    say("Enabled content: " + ", ".join(ordered_plugins))
    if not pfp_plugin:
        say("Patch for Purists is unavailable or has no recognized plugin; it was not enabled.")
    if not delay_plugin:
        say("Expansion Delay is unavailable or has no recognized plugin; it was not enabled.")
    if not mop_core:
        say("Morrowind Optimization Patch is unavailable; the optional core was not installed.")
    return 0


def setup_rebirth(stage_only=False):
    MODS.mkdir(parents=True, exist_ok=True)
    DOWNLOADS.mkdir(parents=True, exist_ok=True)

    met_root = MODS / "Morrowind Enhanced Textures"
    met_staged = stage(
        re.compile(r"morrowind[_ -]+enhanced[_ -]+textures[_ -]+6\.1.*\.zip$", re.IGNORECASE),
        met_root,
        "textures",
        True,
    )
    if not met_staged:
        return 1
    met_data = met_root / "MET 6-1 main"
    met_textures = met_data / "textures"
    if not met_textures.is_dir() or not any(path.is_file() and path.stat().st_size > 0 for path in met_textures.rglob("*")):
        say(f"MET 6.1 did not contain the expected non-empty textures directory: {met_textures}")
        return 1

    rebirth_root = MODS / "Morrowind Rebirth"
    rebirth_staged = stage(
        re.compile(r"morrowind[_ -]+rebirth[_ -]+7\.2.*\.rar$", re.IGNORECASE),
        rebirth_root,
        ("Morrowind Rebirth [Main].ESP", "Morrowind Patch Project v1.6.6 [For Rebirth].esm"),
        True,
    )
    if not rebirth_staged:
        return 1

    rebirth_data = rebirth_root / "Data Files"
    patch_dir = rebirth_root / "Compability Patches"
    main_plugin = rebirth_data / "Morrowind Rebirth [Main].ESP"
    patch_plugin = patch_dir / "Morrowind Patch Project v1.6.6 [For Rebirth].esm"
    if not main_plugin.is_file() or not patch_plugin.is_file():
        say("The Rebirth archive did not contain the expected canonical main plugin and Rebirth patch paths.")
        say(f"Expected: {main_plugin}")
        say(f"Expected: {patch_plugin}")
        return 1

    addon_names = [
        "Morrowind Rebirth - Birthsigns [Addon].ESP",
        "Morrowind Rebirth - Game Settings [Addon].ESP",
        "Morrowind Rebirth - Mercenaries [Addon].ESP",
        "Morrowind Rebirth - Races [Addon].esp",
        "Morrowind Rebirth - Skills [Addon].ESP",
        "Morrowind Rebirth - Tools [Addon].ESP",
    ]
    addon_plugins = [rebirth_data / name for name in addon_names]
    missing_addons = [path.name for path in addon_plugins if not path.is_file()]
    if missing_addons:
        say("The Rebirth archive is missing expected addon plugins:")
        for name in missing_addons:
            say(f"  {name}")
        return 1

    familiar_root = MODS / "Familiar Faces"
    familiar_staged = stage(
        re.compile(r"familiar[_ -]+faces.*\.zip$", re.IGNORECASE),
        familiar_root,
        "Meshes",
        True,
    )
    if not familiar_staged:
        return 1
    if not any(path.is_file() and path.stat().st_size > 0 for path in (familiar_root / "Meshes").rglob("*")):
        say(f"Familiar Faces did not contain non-empty mesh assets under {familiar_root / 'Meshes'}")
        return 1

    herbalism_root = MODS / "Graphic Herbalism"
    herbalism_staged = stage(
        re.compile(r"graphic[_ -]+herbalism.*openmw.*\.7z$", re.IGNORECASE),
        herbalism_root,
        "00 Core + Vanilla Meshes",
        True,
    )
    if not herbalism_staged:
        return 1
    herbalism_core = herbalism_root / "00 Core + Vanilla Meshes"
    if not herbalism_core.is_dir() or not any(path.is_file() and path.stat().st_size > 0 for path in herbalism_core.rglob("*")):
        say(f"Graphic Herbalism did not contain the expected non-empty core data directory: {herbalism_core}")
        return 1

    glow_root = MODS / "Glow in the Dahrk"
    glow_modules = [
        "00 Core",
        "01 Hi Res Window Texture Replacer",
        "03 Nord Glass Windows",
        "05 Raven Rock Glass Windows",
    ]
    glow_staged = stage(
        re.compile(r"glow[_ -]+in[_ -]+the[_ -]+dahrk[_ -]+2\.11\.2.*\.7z$", re.IGNORECASE),
        glow_root,
        tuple(glow_modules),
        True,
    )
    if not glow_staged:
        return 1
    missing_glow_modules = [name for name in glow_modules if not (glow_root / name).is_dir()]
    if missing_glow_modules:
        say("Glow in the Dahrk archive is missing required legacy OpenMW modules:")
        for name in missing_glow_modules:
            say(f"  {name}")
        return 1
    glow_plugins = find_files(glow_root / "05 Raven Rock Glass Windows", "GITD_WL_RR_Interiors.esp")
    if len(glow_plugins) != 1:
        say(f"Expected one GITD_WL_RR_Interiors.esp in {glow_root / '05 Raven Rock Glass Windows'}")
        return 1

    lgnpc_root = MODS / "LGNPC Dialogue Only"
    lgnpc_staged = stage(
        re.compile(r"lgnpc[_ -]+merged[_ -]+lt.*\.zip$", re.IGNORECASE),
        lgnpc_root,
        "LGNPC_Merged_Lt.esp",
    )
    if not lgnpc_staged:
        say("Optional LGNPC Dialogue Only archive was found but did not validate; the profile was not changed.")
        return 1
    lgnpc_plugins = find_files(lgnpc_root, "LGNPC_Merged_Lt.esp") if lgnpc_root.is_dir() else []
    if len(lgnpc_plugins) > 1:
        say(f"Expected at most one LGNPC_Merged_Lt.esp under {lgnpc_root}")
        return 1

    if stage_only:
        say("Rebirth profile archive staged; Steam game discovery was skipped.")
        return 0

    game = find_game()
    if game is None:
        say("Morrowind, Tribunal, Bloodmoon, and Morrowind.ini were not found in Steam libraries.")
        say("Install Morrowind in Steam, then run morrowind-setup --profile rebirth again.")
        return 1
    game_root, game_data, ini = game

    ordered_plugins = [
        "Morrowind.esm",
        "Tribunal.esm",
        "Bloodmoon.esm",
        patch_plugin.name,
        main_plugin.name,
        *[path.name for path in addon_plugins],
    ]
    ordered_plugins.append(glow_plugins[0].name)
    if lgnpc_plugins:
        ordered_plugins.append(lgnpc_plugins[0].name)
    if refuse_unknown_content("Rebirth", ordered_plugins):
        return 1

    fallbacks = import_game_fallbacks(game_data, ini)
    if fallbacks is None:
        return 1

    familiar_optional = familiar_root / "(optional) Redguard Female Teeth Texture Fix"
    data_dirs = [game_data, met_data, rebirth_data, patch_dir, familiar_root]
    if familiar_optional.is_dir():
        data_dirs.append(familiar_optional)
    data_dirs.append(herbalism_core)
    data_dirs.extend(glow_root / name for name in glow_modules)
    if lgnpc_plugins:
        data_dirs.append(lgnpc_plugins[0].parent)
    write_profile_config("rebirth", data_dirs, ordered_plugins, fallbacks)
    say(f"Game files: {game_root}")
    if not lgnpc_plugins:
        say("Optional LGNPC Dialogue Only archive was not found; it was not enabled.")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--profile",
        choices=("rebirth", "tr", "all"),
        default="rebirth",
        help="profile to configure (default: rebirth)",
    )
    parser.add_argument(
        "--stage-only",
        action="store_true",
        help="extract and validate profile archives without requiring Steam game files",
    )
    args = parser.parse_args()
    profiles = ("rebirth", "tr") if args.profile == "all" else (args.profile,)
    result = 0
    for profile in profiles:
        global CONFIG, CFG
        config_root, _data_root = PROFILE_ROOTS[profile]
        CONFIG = config_root / "openmw"
        CFG = CONFIG / "openmw.cfg"
        if profile == "tr":
            current = setup_tr(stage_only=args.stage_only)
        else:
            current = setup_rebirth(stage_only=args.stage_only)
        result = max(result, current)
    return result


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        say(f"Command failed with exit status {error.returncode}: {error.cmd}")
        raise SystemExit(error.returncode)
