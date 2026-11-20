#!/usr/bin/env python3
"""Set up isolated Rebirth and Tamriel Rebuilt profiles for OpenMW."""

import argparse
import fcntl
import hashlib
import os
import re
import shutil
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path


HOME = Path.home()
DATA_HOME = Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local/share")
CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config")
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


class SetupError(Exception):
    pass


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


def nonempty_file(path):
    return path.is_file() and path.stat().st_size > 0


def matching_plugins(root, names):
    return {path for name in names for path in find_files(root, name)}


def staged_tree(root, pattern):
    trees = [path for path in root.glob(pattern) if path.is_dir()]
    if len(trees) == 1 and any(nonempty_file(file) for file in trees[0].rglob("*")):
        return trees[0]
    return None


def extract_archive(archive, destination, valid):
    with tempfile.TemporaryDirectory(prefix=f".{destination.name}.extract-", dir=MODS) as temp_name:
        temp = Path(temp_name)
        say(f"Extracting {archive.name} to {destination}")
        if archive.suffix.casefold() == ".rar":
            subprocess.run(["unrar", "x", "-o+", "-idq", str(archive), f"{temp}/"], check=True)
        else:
            subprocess.run(["7zz", "x", "-y", f"-o{temp}", str(archive)], check=True)
        if not valid(temp):
            raise SetupError(f"{archive.name} has an invalid or ambiguous layout. Left {destination} in place.")
        (temp / ".morrowind-setup-ready").touch()
        backup = None
        if destination.exists():
            protect_configured_data_dirs(destination, temp)
            stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
            backup = destination.with_name(f"{destination.name}.previous-{stamp}")
            os.replace(destination, backup)
            say(f"Moved incomplete prior extraction to {backup}")
        try:
            os.replace(temp, destination)
        except OSError:
            if backup is not None:
                os.replace(backup, destination)
            raise


def stage(pattern, destination, checksum, *, required=False, files=(), trees=(), plugins=()):
    def valid(root):
        if not root.is_dir():
            return False
        if not all(nonempty_file(root / path) for path in files):
            return False
        if not all(staged_tree(root, pattern) for pattern in trees):
            return False
        for subdir, names in plugins:
            matches = matching_plugins(root / subdir, names)
            if len(matches) != 1 or not nonempty_file(next(iter(matches))):
                return False
        return True

    if (destination / ".morrowind-setup-ready").is_file() and valid(destination):
        say(f"Already extracted: {destination}")
        return destination
    archives = find_archives(pattern)
    if not archives and not required:
        if not destination.exists():
            return None
        if valid(destination):
            say(f"Using existing extraction: {destination}")
            return destination
    for archive in archives:
        with archive.open("rb") as stream:
            if hashlib.file_digest(stream, "sha256").hexdigest() != checksum:
                continue
        extract_archive(archive, destination, valid)
        return destination
    raise SetupError(
        f"{destination.name}: expected an archive matching {pattern.pattern!r} in {DOWNLOADS} "
        f"or ~/Downloads with SHA-256 {checksum}. Left {destination} in place."
    )


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


def require_game():
    game = find_game()
    if game is None:
        raise SetupError("Install Morrowind, Tribunal, and Bloodmoon in Steam, then rerun setup.")
    return game


def staged_plugin(root, names):
    return next(iter(matching_plugins(root, names)))


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


def config_entry(line):
    key, separator, value = line.partition("=")
    if not separator or key.lstrip().startswith("#"):
        return "", ""
    return key.strip().casefold(), value.strip().strip('"')


def protect_configured_data_dirs(destination, replacement):
    destination = Path(os.path.abspath(destination))
    resolved_destination = destination.resolve()
    for config_root, _ in PROFILE_ROOTS.values():
        config = config_root / "openmw/openmw.cfg"
        if not config.is_file():
            continue
        for line in config.read_text(errors="replace").splitlines():
            key, value = config_entry(line)
            if key != "data":
                continue
            path = Path(os.path.abspath(config.parent / value))
            if not path.is_dir():
                continue
            if path.is_relative_to(destination):
                subdir = path.relative_to(destination)
            else:
                resolved_path = path.resolve()
                if not resolved_path.is_relative_to(resolved_destination):
                    continue
                subdir = resolved_path.relative_to(resolved_destination)
            if not (replacement / subdir).is_dir():
                raise SetupError(
                    f"Replacing {destination} would remove configured data directory {path} in {config}. "
                    "Move the data outside the staged mod and update the profile before rerunning setup."
                )


def managed_data_path(value, data_dirs, mod_roots):
    path = (CONFIG / value).resolve()
    return (
        path in data_dirs
        or (not path.is_dir() and any(path.is_relative_to(root) for root in mod_roots))
        or tuple(part.casefold() for part in path.parts[-4:]) == ("steamapps", "common", "morrowind", "data files")
    )


def write_profile_config(profile, data_dirs, ordered_plugins, fallbacks, managed_roots):
    existing_lines = CFG.read_text(errors="replace").splitlines() if CFG.exists() else []
    unique_data_dirs = list(dict.fromkeys(path.resolve() for path in data_dirs))
    mod_roots = [path.resolve() for path in managed_roots]
    header = "# Generated by morrowind-setup; OpenMW Launcher may edit this file."
    game_archives = [line for line in fallbacks if config_entry(line)[0] == "fallback-archive"]
    archive_names = {config_entry(line)[1].casefold() for line in game_archives}
    preserved_lines = []
    existing_fallbacks = set()
    for line in existing_lines:
        key, value = config_entry(line)
        if line.strip() == header or key in {"content", "user-data", "data-local"}:
            continue
        if key == "data" and managed_data_path(value, unique_data_dirs, mod_roots):
            continue
        if key == "fallback-archive" and value.casefold() in archive_names:
            continue
        if key == "fallback":
            existing_fallbacks.add(value.partition(",")[0].strip().casefold())
        preserved_lines.append(line)

    lines = [header, *game_archives]
    lines.extend(f'data="{path}"' for path in unique_data_dirs)
    lines.extend(preserved_lines)
    lines.extend(
        line for line in fallbacks
        if config_entry(line)[0] == "fallback"
        and config_entry(line)[1].partition(",")[0].strip().casefold() not in existing_fallbacks
    )
    lines.extend(f"content={plugin}" for plugin in ordered_plugins)
    profile_data = PROFILE_ROOTS[profile][1] / "openmw"
    profile_data.mkdir(parents=True, exist_ok=True)
    (profile_data / "data").mkdir(parents=True, exist_ok=True)
    lines.append(f'user-data="{profile_data}"')
    lines.append(f'data-local="{profile_data / "data"}"')
    CONFIG.mkdir(parents=True, exist_ok=True)
    if CFG.exists():
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
        backup = CFG.with_name(f"openmw.cfg.bak-{stamp}")
        shutil.copy2(CFG, backup)
        say(f"Backed up existing config to {backup}")
    with tempfile.NamedTemporaryFile(mode="w", prefix=".openmw.cfg-", dir=CONFIG, delete=False) as stream:
        temp_cfg = Path(stream.name)
        try:
            stream.write("\n".join(lines) + "\n")
            stream.close()
            try:
                with (CONFIG / "launcher.cfg").open("x") as launcher:
                    launcher.write("[General]\nfirstrun=false\n")
            except FileExistsError:
                pass
            os.replace(temp_cfg, CFG)
        finally:
            temp_cfg.unlink(missing_ok=True)
    say(f"OpenMW {profile} config written: {CFG}")
    say("Enabled content: " + ", ".join(ordered_plugins))


def configure_profile(profile, game_root, game_data, ini, data_dirs, plugins, managed_roots):
    ordered_plugins = ["Morrowind.esm", "Tribunal.esm", "Bloodmoon.esm", *(path.name for path in plugins)]
    if refuse_unknown_content(profile, ordered_plugins):
        return 1
    fallbacks = import_game_fallbacks(game_data, ini)
    if fallbacks is None:
        return 1
    write_profile_config(profile, data_dirs, ordered_plugins, fallbacks, managed_roots)
    say(f"Game files: {game_root}")
    return 0


def setup_tr(stage_only=False):
    tr_main = ("TR_Mainland.esm",)
    tr_scripts = ("tamrielrebuilt.omwscripts",)
    td_main = ("Tamriel_Data.esm",)
    td_scripts = ("Tamriel_Data.omwscripts",)
    pfp_names = ("Patch for Purists.esm", "Patch for Purists.esp")
    delay_names = ("Expansion Delay.esp",)

    tr_root = stage(
        re.compile(r"tamriel[_ -]?rebuilt.*\.7z$", re.IGNORECASE),
        MODS / "Tamriel Rebuilt", "31d1f45469291cd71408fe7b795ded0e593fab226796aa35b1b86b588825c0bc",
        required=True, plugins=((".", tr_main), (".", tr_scripts)),
    )
    td_root = stage(
        re.compile(r"tamriel[_ -]?data.*26\.08.*hd.*\.7z$", re.IGNORECASE),
        MODS / "Tamriel Data HD", "da5b37375434c265c47f484c4f005cf7e279bcaa1cccc39bf56c92d5bf8f5cda",
        required=True, plugins=((".", td_main), (".", td_scripts)),
    )
    pfp_root = stage(
        re.compile(r"patch[_ -]+for[_ -]+purists.*\.(?:7z|zip)$", re.IGNORECASE),
        MODS / "Patch for Purists", "e8ccaeb08c224b28c385f3c78b7f9f04ea8cbdacd786f5e56766587f856f4786", plugins=((".", pfp_names),),
    )
    delay_root = stage(
        re.compile(r"expansion[_ -]+delay.*\.(?:7z|zip)$", re.IGNORECASE),
        MODS / "Expansion Delay", "09f34ff768f54765ea15e7a85b36b6cfd80ade412ebc9359ba9aed77908ffe72", plugins=((".", delay_names),),
    )
    mop_root = stage(
        re.compile(r"morrowind[_ -]+optimization[_ -]+patch.*\.(?:7z|zip)$", re.IGNORECASE),
        MODS / "Morrowind Optimization Patch", "270da1846414b1213f67d1a40f1c065e14e7859a486c3cb184779452a80b9d71",
        trees=("**/00 Core",),
    )
    if stage_only:
        say("TR profile archives staged; Steam game discovery was skipped.")
        return 0

    game_root, game_data, ini = require_game()
    plugins = []
    if pfp_root:
        plugins.append(staged_plugin(pfp_root, pfp_names))
    plugins.extend([
        staged_plugin(td_root, td_main),
        staged_plugin(td_root, td_scripts),
        staged_plugin(tr_root, tr_main),
        staged_plugin(tr_root, tr_scripts),
    ])
    if "tr_factions.esp" in existing_content():
        matches = find_files(tr_root, "TR_Factions.esp")
        if len(matches) != 1 or not nonempty_file(matches[0]):
            raise SetupError("Expected one TR_Factions.esp for the existing Tamriel Rebuilt configuration.")
        plugins.append(matches[0])
    if delay_root:
        plugins.append(staged_plugin(delay_root, delay_names))

    data_dirs = [game_data, *(path.parent for path in plugins)]
    if mop_root:
        data_dirs.append(staged_tree(mop_root, "**/00 Core"))
    managed_roots = [MODS / name for name in (
        "Tamriel Rebuilt", "Tamriel Data HD", "Patch for Purists",
        "Expansion Delay", "Morrowind Optimization Patch",
    )]
    return configure_profile("tr", game_root, game_data, ini, data_dirs, plugins, managed_roots)


def setup_rebirth(stage_only=False):
    rebirth_data = "Data Files"
    patch_dir = "Compability Patches"
    main_plugin = "Morrowind Rebirth [Main].ESP"
    patch_plugin = "Morrowind Patch Project v1.6.6 [For Rebirth].esm"
    addon_names = [
        "Morrowind Rebirth - Birthsigns [Addon].ESP",
        "Morrowind Rebirth - Game Settings [Addon].ESP",
        "Morrowind Rebirth - Mercenaries [Addon].ESP",
        "Morrowind Rebirth - Races [Addon].esp",
        "Morrowind Rebirth - Skills [Addon].ESP",
        "Morrowind Rebirth - Tools [Addon].ESP",
    ]
    glow_modules = (
        "00 Core",
        "01 Hi Res Window Texture Replacer",
        "03 Nord Glass Windows",
        "05 Raven Rock Glass Windows",
    )
    glow_plugin = ("GITD_WL_RR_Interiors.esp",)
    lgnpc_plugin = ("LGNPC_Merged_Lt.esp",)

    met_root = stage(
        re.compile(r"morrowind[_ -]+enhanced[_ -]+textures[_ -]+6\.1.*\.zip$", re.IGNORECASE),
        MODS / "Morrowind Enhanced Textures", "3f029c979f80c8c92095b60c50ee688352c3ca36f036ab32a52201a119c9e52f",
        required=True, trees=("MET 6-1 main/textures",),
    )
    rebirth_root = stage(
        re.compile(r"morrowind[_ -]+rebirth[_ -]+7\.2.*\.rar$", re.IGNORECASE),
        MODS / "Morrowind Rebirth", "8f31db65c01e41744842c10151a3a5259e1e57668e6f89e444b10a73a2a20ee0",
        required=True,
        files=(
            f"{patch_dir}/{patch_plugin}",
            *(f"{rebirth_data}/{name}" for name in (main_plugin, *addon_names)),
        ),
    )
    familiar_root = stage(
        re.compile(r"familiar[_ -]+faces.*\.zip$", re.IGNORECASE),
        MODS / "Familiar Faces", "650f44032fec42a423a11b06f550b38d878c1b2f92b62ac6d94329287364d162", required=True, trees=("Meshes",),
    )
    herbalism_core = "00 Core + Vanilla Meshes"
    herbalism_root = stage(
        re.compile(r"graphic[_ -]+herbalism.*openmw.*\.7z$", re.IGNORECASE),
        MODS / "Graphic Herbalism", "3ae31e146fa1ccf6ed82d0e2dc85fe317ef14c0c72202ca383e9ca0b57745c0c", required=True, trees=(herbalism_core,),
    )
    glow_root = stage(
        re.compile(r"glow[_ -]+in[_ -]+the[_ -]+dahrk[_ -]+2\.11\.2.*\.7z$", re.IGNORECASE),
        MODS / "Glow in the Dahrk", "d31b57bb48c084c6b77b2eb768afae9f225f3e4fbb59feecdb123fb940f1c6c4",
        required=True, trees=glow_modules, plugins=((glow_modules[-1], glow_plugin),),
    )
    lgnpc_root = stage(
        re.compile(r"lgnpc[_ -]+merged[_ -]+lt.*\.zip$", re.IGNORECASE),
        MODS / "LGNPC Dialogue Only", "3be2f3f53248976f0a7671ec424830393cddb4fc412bc2e3111c405318a7ddc6", plugins=((".", lgnpc_plugin),),
    )
    if stage_only:
        say("Rebirth profile archives staged; Steam game discovery was skipped.")
        return 0

    game_root, game_data, ini = require_game()
    plugins = [
        rebirth_root / patch_dir / patch_plugin,
        *(rebirth_root / rebirth_data / name for name in (main_plugin, *addon_names)),
        staged_plugin(glow_root / glow_modules[-1], glow_plugin),
    ]
    data_dirs = [
        game_data, met_root / "MET 6-1 main", rebirth_root / rebirth_data,
        rebirth_root / patch_dir, familiar_root,
    ]
    familiar_optional = familiar_root / "(optional) Redguard Female Teeth Texture Fix"
    if familiar_optional.is_dir():
        data_dirs.append(familiar_optional)
    data_dirs.append(herbalism_root / herbalism_core)
    data_dirs.extend(glow_root / module for module in glow_modules)
    if lgnpc_root:
        plugins.append(staged_plugin(lgnpc_root, lgnpc_plugin))
        data_dirs.append(plugins[-1].parent)
    managed_roots = [
        met_root, rebirth_root, familiar_root, herbalism_root, glow_root, MODS / "LGNPC Dialogue Only",
    ]
    return configure_profile("rebirth", game_root, game_data, ini, data_dirs, plugins, managed_roots)


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
    OPENMW_HOME.mkdir(parents=True, exist_ok=True)
    with (OPENMW_HOME / ".morrowind-setup.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        MODS.mkdir(exist_ok=True)
        DOWNLOADS.mkdir(exist_ok=True)
        result = 0
        for profile in profiles:
            global CONFIG, CFG
            config_root, _data_root = PROFILE_ROOTS[profile]
            CONFIG = config_root / "openmw"
            CFG = CONFIG / "openmw.cfg"
            setup = setup_tr if profile == "tr" else setup_rebirth
            try:
                current = setup(stage_only=args.stage_only)
            except SetupError as error:
                say(str(error))
                current = 1
            result = max(result, current)
    return result


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        say(f"Command failed with exit status {error.returncode}: {error.cmd}")
        raise SystemExit(error.returncode)
