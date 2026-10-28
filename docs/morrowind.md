# Morrowind on thorny

`thorny` runs the Steam copy of Morrowind with native OpenMW. The setup keeps
two independent profiles: Morrowind Rebirth is the default, and Tamriel Rebuilt
(TR) retains the existing mainland setup. Each profile has its own plugins,
configuration, and saves. Both use the same Steam game files and share the
download and staged-mod directories.

For a fresh installation, sign into Steam on `thorny` and install Morrowind,
Steam app `22320`. If Steam disables Install, select
Proton under the game's Compatibility properties to allow the download.
OpenMW runs the game natively; the original Windows executable need not run.

The profiles' launchers and all mod archives are installed on thorny as of
October 27, 2026. The Nix changes still need to reach `main` so a future
automatic deployment preserves the packages.

## Commands and profile files

Run the setup after installing Morrowind in Steam:

```bash
morrowind-setup                         # Rebirth, the default
morrowind-setup --profile rebirth
morrowind-setup --profile tr
morrowind-setup --profile all           # Configure both profiles
morrowind-setup --profile rebirth --stage-only
```

`--stage-only` stages the selected profile's mod files without writing its
OpenMW configuration. The launch commands are `morrowind` (Rebirth),
`morrowind-rebirth`, and `morrowind-tr`. The desktop menu has **Morrowind
Rebirth** and **Morrowind Tamriel Rebuilt** entries.

| Profile | OpenMW configuration | Saves |
| --- | --- | --- |
| Rebirth | `~/.config/morrowind/rebirth/openmw/openmw.cfg` | `~/.local/share/morrowind/rebirth/openmw/saves/` |
| Tamriel Rebuilt | `~/.config/morrowind/tr/openmw/openmw.cfg` | `~/.local/share/morrowind/tr/openmw/saves/` |

The setup leaves the original `~/.config/openmw/` and
`~/.local/share/openmw/saves/` in place and does not use them for either
profile. Archives and staged mods are shared in `~/.local/share/openmw/`, under
`downloads/` and `mods/`.

## Morrowind Rebirth

Download the [Rebirth 7.2 release](https://www.moddb.com/mods/morrowind-rebirth/downloads/release-morrowind-rebirth-72)
archive, save it as `Morrowind_Rebirth_7.2.rar`, and place it in `~/Downloads` or
`~/.local/share/openmw/downloads/`. The archive contains duplicate alternate
versions of some files; use the named files below and ignore the `Alternate
Version` copies.

| Mod | Version and source | Files and order |
| --- | --- | --- |
| Morrowind Enhanced Textures (MET) | 6.1, [Nexus 46221](https://www.nexusmods.com/morrowind/mods/46221) | Load before Rebirth |
| Morrowind Rebirth | 7.2, [ModDB](https://www.moddb.com/mods/morrowind-rebirth/downloads/release-morrowind-rebirth-72) | `Data Files/Morrowind Rebirth [Main].ESP`, then the six `Data Files` add-ons: Birthsigns, Game Settings, Mercenaries, Races, Skills, and Tools |
| Morrowind Patch Project | 1.6.6, included in Rebirth archive | `Compability Patches/Morrowind Patch Project v1.6.6 [For Rebirth].esm`, before Rebirth |
| Familiar Faces | 2.1, [Nexus 50093](https://www.nexusmods.com/morrowind/mods/50093) | After Rebirth; the archive also includes the optional Redguard Teeth fix |
| Graphic Herbalism | 1.04, [Nexus 46599](https://www.nexusmods.com/morrowind/mods/46599) | Install only its core files and vanilla meshes, after Rebirth |
| Glow in the Dahrk | 2.11.2, [legacy OpenMW release](https://www.nexusmods.com/morrowind/mods/45886) | Use `00 Core`, `01 Hi Res Window Texture Replacer`, `03 Nord Glass Windows`, and `05 Raven Rock Glass Windows`; enable `GITD_WL_RR_Interiors.esp` |
| LGNPC Dialogue Only merged | [Official download](http://lgnpc.org/dialogue-only-downloads) | Included in this setup; the merged archive supplies `LGNPC_Merged_Lt.ESP` |

The generated content order is `Morrowind.esm`, `Tribunal.esm`,
`Bloodmoon.esm`, the Rebirth Patch Project file, the Rebirth main plugin, its
six add-ons, `GITD_WL_RR_Interiors.esp`, and `LGNPC_Merged_Lt.ESP` if that
optional archive is present. The helper applies the Redguard Teeth fix included
in the Familiar Faces archive.

The current Rebirth release does not include a main-quest overhaul. Keep TR,
Patch for Purists, Morrowind Optimization Patch, and Expansion Delay out of this
profile. Rebirth's author supports OpenMW but warns that TR can conflict with
its models and balance; the [compatibility notes](https://www.moddb.com/mods/morrowind-rebirth/tutorials/compatibility)
also specify the bundled Rebirth patch in place of Patch for Purists. Keep the two
profiles separate rather than combining their plugin lists.

The launcher also lists Rebirth's bundled compatibility patches for Julan,
Project Cyrodiil, Skyrim: Home of the Nords, Siege at Firemoth, and Uvirith's
Legacy. Leave these unchecked; the corresponding mods are not installed.

For a fresh installation, save the legacy Glow archive as
`Glow_in_the_Dahrk_2.11.2.7z`. Keep the original Nexus filenames for MET,
Familiar Faces, and Graphic Herbalism. All selected archives are already
downloaded and extracted on thorny.

Recorded SHA-256 hashes of the downloaded Rebirth archives:

| Archive | SHA-256 |
| --- | --- |
| Rebirth 7.2 | `8f31db65c01e41744842c10151a3a5259e1e57668e6f89e444b10a73a2a20ee0` |
| MET 6.1 | `3f029c979f80c8c92095b60c50ee688352c3ca36f036ab32a52201a119c9e52f` |
| Familiar Faces 2.1 | `650f44032fec42a423a11b06f550b38d878c1b2f92b62ac6d94329287364d162` |
| Graphic Herbalism 1.04 | `3ae31e146fa1ccf6ed82d0e2dc85fe317ef14c0c72202ca383e9ca0b57745c0c` |
| Glow in the Dahrk 2.11.2 | `d31b57bb48c084c6b77b2eb768afae9f225f3e4fbb59feecdb123fb940f1c6c4` |
| LGNPC Dialogue Only | `3be2f3f53248976f0a7671ec424830393cddb4fc412bc2e3111c405318a7ddc6` |

## Tamriel Rebuilt

The TR profile keeps the existing five-mod setup:

| Mod | Version | SHA-256 |
| --- | --- | --- |
| Tamriel Rebuilt | 26.08a | `31d1f45469291cd71408fe7b795ded0e593fab226796aa35b1b86b588825c0bc` |
| Tamriel Data HD | 26.08 | `da5b37375434c265c47f484c4f005cf7e279bcaa1cccc39bf56c92d5bf8f5cda` |
| Patch for Purists | 5.0.7 | `e8ccaeb08c224b28c385f3c78b7f9f04ea8cbdacd786f5e56766587f856f4786` |
| Expansion Delay | 1.3 | `09f34ff768f54765ea15e7a85b36b6cfd80ade412ebc9359ba9aed77908ffe72` |
| Morrowind Optimization Patch | 1.18.0 | `270da1846414b1213f67d1a40f1c065e14e7859a486c3cb184779452a80b9d71` |

Download Tamriel Rebuilt and Tamriel Data HD from the [TR main release](https://www.tamriel-rebuilt.org/downloads/main-release)
and [Tamriel Data resources](https://www.tamriel-rebuilt.org/downloads/resources).
Use `Tamriel_Rebuilt_26.08a.7z` and `Tamriel_Data_26.08_HD.7z`. Nexus requires
an account for [Patch for Purists](https://www.nexusmods.com/morrowind/mods/45096),
[Morrowind Optimization Patch](https://www.nexusmods.com/morrowind/mods/45384),
and [Expansion Delay](https://www.nexusmods.com/morrowind/mods/47588). Keep the
archive names intact. TR and Tamriel Data are required together; use only one
Tamriel Data resolution package.

Expected enabled plugin order:

```text
Morrowind.esm
Tribunal.esm
Bloodmoon.esm
Patch for Purists.esm
Tamriel_Data.esm
Tamriel_Data.omwscripts
TR_Mainland.esm
tamrielrebuilt.omwscripts
Expansion Delay.ESP  (if installed)
```

Morrowind Optimization Patch contributes its `00 Core` meshes and has no
plugin. `TR_Factions.esp` stays disabled by default because it changes faction
dialogue and progression. Enable it only if you want those changes. Start a new
character after a major TR update. Do not enable stale `TR_Travels.esp` or
`TR_Preview.esp` files; TR includes Firemoth, so do not load `Siege at
Firemoth.esp` alongside it.

## Recovery and references

Setup makes timestamped `openmw.cfg.bak-*` backups beside the selected
profile's config and refuses to replace an unknown plugin list. Launchers
automatically run setup only when that profile's `openmw.cfg` is missing, so
normal launcher edits persist. The helper does not upgrade an already-staged
mod just because a newer archive is downloaded.

After importing the game, setup initializes a missing `launcher.cfg` with
`firstrun=false` so the launcher opens the prepared profile without offering
the installation wizard. Existing launcher preferences are preserved.

If a launcher shows the wrong plugins, check the selected profile's
`openmw.cfg` and rerun setup for that profile. Keep each profile's configuration
and save directory together when making a backup. Do not copy mod files into
Steam's game installation.

OpenMW reads the game data installed by Steam and runs without Proton. The
[OpenMW modding guide](https://modding-openmw.com/tips/installing-mods/)
explains data paths and plugin ordering. See the [TR installation guide](https://www.tamriel-rebuilt.org/content/how-install-tamriel-rebuilt)
and [release notes](https://www.tamriel-rebuilt.org/downloads/release-notes)
for its current installation steps and save compatibility notes.

## Verification

The Nix build, activation, and Linux `nix flake check --no-build` passed.
All selected archives extracted successfully. The actual plugins' master
dependencies are satisfied in the generated order. Separate-profile checks
used these real mods with synthetic base-game fixtures to verify plugin and
asset isolation, save paths, backups, reruns, and unknown-plugin refusal.
The Steam download is now installed and the Rebirth launcher has been opened
on the desktop. In-game testing is in progress.
