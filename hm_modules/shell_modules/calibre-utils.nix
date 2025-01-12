{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.shell.calibre-utils;
  calibre-utils = pkgs.writers.writePython3Bin "calibre-utils" {libraries = with pkgs.python3Packages; [tabulate typer rich];} ''
    import contextlib
    import json
    import os
    import re
    import statistics
    import shutil
    import subprocess
    import tempfile
    from dataclasses import dataclass
    from datetime import datetime
    from pathlib import Path
    from typing import Optional
    import typer
    from rich.prompt import Confirm, Prompt
    from rich import print
    from tabulate import tabulate


    @dataclass
    class Track:
        num: int
        start: int
        end: int
        title: str
        bitrate: int
        timebase: str = "1/1000"

        def as_txt(self) -> str:
            return (
                f"[CHAPTER]\nTIMEBASE={self.timebase}\n"
                f"START={self.start}\nEND={self.end}\n"
                f"title={self.title}\n"
                "\n"
            )

        def as_row(self) -> tuple[int, str, str]:
            return (self.num, self.title, f"{int(self.bitrate / 1000)}k")  # noqa: E501

        def __iadd__(self, other: "Track") -> None:
            self.title = (
                self.title
                if len(self.title) < len(other.title)
                else other.title
            )
            self.start = min((self.start, other.start))
            self.end = max((self.end, other.end))
            return None


    cli = typer.Typer()
    audio = typer.Typer(name="calibre-utils")
    cli.add_typer(audio, name="audio", help="Audio book related commands")


    def get_duration_bitrate(filename: Path) -> Optional[tuple[int, int]]:  # noqa: E501
        cmd: list[str] = [
            '${pkgs.ffmpeg}/bin/ffprobe',  # noqa: E501
            '-v', 'error',
            '-show_entries', 'stream=bit_rate:format=duration',
            '-of', 'default=noprint_wrappers=1:nokey=1',
            str(filename)
        ]
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                check=True,
            )
        except subprocess.CalledProcessError as e:
            print(f"[red]Error processing {filename}: {e}[/red]")
            return None
        try:
            # $ ffprobe -v error -show_entries stream=bit_rate:format=duration -of default=noprint_wrappers=1:nokey=1 ....mp3  # noqa: E501
            # 51359
            # N/A
            # 1479.888000
            bitrate, _, duration = result.stdout.strip().split("\n")
            return int(float(duration) * 1000), int(bitrate)
        except Exception:
            print(f"[red]Unexpected output from ffprobe:[/red]\n{result.stdout}\n")
            return None


    @audio.command()
    def concat_tracks(
        name: str = typer.Argument(
            "notgiven",
            help="The name of the output file, defaulting to the directory name.",
        ),
        directory: Path = typer.Argument(
            Path("."),
            help="Directory containing audio files",
            exists=True,
            file_okay=False,
            dir_okay=True,
        ),
        pattern: str = typer.Option(
            "*.mp3",
            "--pattern", "-p",
            help="File pattern to match (e.g., *.mp3, *.m4a)",
        )
    ) -> None:
        """
        Combine individual audio book tracks into one .m4b file
        for use with audio book readers.
        """
        files: list[Path] = sorted(directory.glob(pattern))
        if not files:
            print(f"[yellow]No {pattern} files found in {directory}[/yellow]")
            raise typer.Exit(1)
        tracks: dict[int, Track] = {}
        timestamp: int = 0
        title_pattern = re.compile(r"^(?P<track_num>\d+) - (?P<title>.*)")
        for file in files:
            title_match = re.match(title_pattern, file.stem)
            if not title_match:
                print("[red]Unable to extract track num and chapter title from file name[/red]")  # noqa: E501
                print(f"use this title pattern: {title_pattern}")
                raise typer.Exit(1)
            duration_bitrate = get_duration_bitrate(file)
            if duration_bitrate is None:
                return None
            duration, bitrate = duration_bitrate
            chapter_title = title_match["title"]
            track_num = int(title_match["track_num"])
            track = Track(
                 num=track_num,
                 start=timestamp,
                 end=timestamp + duration,
                 title=chapter_title,
                 bitrate=bitrate,
            )
            if existing_track := tracks.get(track_num):
                existing_track += track
            else:
                tracks[track_num] = track
            timestamp += duration
        print(f"[green]✓[/green] Metadata from {len(files)} files collecting into {len(tracks)} chapters/tracks.")  # noqa: E501

        for i, track in enumerate(sorted(tracks.values(), key=lambda t: t.num)):
            track.num = i + 1

        print(
            tabulate(
                (track.as_row() for track in sorted(tracks.values(), key=lambda t: t.num)),  # noqa: E501
                headers=["#", "Title", "Bitrate"],
                tablefmt="simple",
            )
        )
        chapters_txt = directory / "chapters.txt"
        try:
            chapters_txt.write_text("")  # clear in case of prev run
            with chapters_txt.open(mode="a") as fp:
                fp.write(";FFMETADATA1\n")
                for track_num in sorted(tracks):
                    track = tracks[track_num]
                    fp.write(track.as_txt())
        except Exception as e:
            print(f"[red]Error writing metadata file: {e}[/red]")
            raise typer.Exit(3)
        mbitrate = int(statistics.median(t.bitrate for t in tracks.values()) / 1000)  # noqa: E501
        # find the closest target bit rate from the mean bitrate
        target_bitrate = min([24, 48, 64, 128, 256, 320], key=lambda n: abs(n-mbitrate))  # noqa: E501
        print(f"[green]✓[/green] Target bitrate): {target_bitrate}kbps")
        if not Confirm.ask("[yellow]?[/yellow] Track list and bitrate look good?"):
            print("The files must be sorted in lexographical sort order. prepend the order.")  # noqa: E501
            print("e.g. [cyan]001 - Prologue.mp3[/cyan]")
            print("e.g. [cyan]002 - Chapter 1.mp3[/cyan]")
            print("e.g. [cyan]003 - Chapter 2.mp3[/cyan]")
            print("e.g. [cyan]004 - Chapter 3 pt1.mp3[/cyan]")
            print("e.g. [cyan]004 - Chapter 3 pt2.mp3[/cyan]")
            raise typer.Exit(2)
        input_files = directory / "input_files.txt"
        input_files.write_text("\n".join(f"file '{f.as_posix()}'" for f in files))
        output_file_name = name if name != "notgiven" else directory.absolute().stem  # noqa: E501
        output_file_name = Prompt.ask("Name of the book:", default=output_file_name)  # noqa: E501
        print(f"[green]✓[/green] Merging files to create audio book [cyan]{output_file_name}.m4b[/cyan] @ {target_bitrate}kbps...")  # noqa: E501
        ffmpg_cmd = [
            "${pkgs.ffmpeg}/bin/ffmpeg",  # noqa: E501
            "-f",
            "concat",
            "-safe",
            "0",
            "-i",
            "input_files.txt",
            "-i",
            f"{chapters_txt}",
            "-map",
            "0:a",
            "-map_metadata",
            "1",
            "-c:a",
            "aac",
            "-b:a",
            f"{target_bitrate}k",
            f"{output_file_name}.m4b"
        ]
        try:
            result = subprocess.run(
                ffmpg_cmd,
                capture_output=True,
                text=True,
                check=True,
            )
        except subprocess.CalledProcessError as e:
            print(f"[red]ffmpg error:\n{e}[/red]")
            print(f"[red]{result.stderr.strip()}[/red]")
            typer.Exit(4)
        print(
            f"[green]✓[/green] Success! Combined {len(files)} tracks into "
            f"[cyan]{output_file_name}.m4b[/cyan]"
            f" encoded at [green]{target_bitrate}kbps[/green]"
        )
        if Confirm.ask("Clean up files?"):
            for f in files:
                with contextlib.suppress(Exception):
                    f.unlink()
            with contextlib.suppress(Exception):
                input_files.unlink()
            with contextlib.suppress(Exception):
                (Path(".") / "chapters.txt").unlink()


    def _get_default_calibre_library_path() -> Path:
        cfg_dir = Path(os.environ.get("XDG_CONFIG_HOME", "~/.config")).absolute()  # noqa: E501
        if (cfg_file := cfg_dir / "calibre/global.py.json") and cfg_file.exists():
            calibre_config = json.loads(cfg_file.read_text())
            _lib_path = calibre_config.get("library_path")
            if (lib_path := _lib_path) and Path(lib_path).exists():
                return Path(lib_path)
        print("[red]Unable to determine default calibre library path.[/red]")
        raise typer.Exit(5)


    @cli.command()
    def backup(
        calibre_library: Path = typer.Argument(
            default_factory=_get_default_calibre_library_path,
            help="calibre library directory to backub",
            exists=True,
            file_okay=False,
            dir_okay=True,
        ),
    ) -> None:
        """
        Export the default calibre library to a tmpdir, create
        bz2 compressed tarball and optionally upload it to mega
        """
        with tempfile.TemporaryDirectory() as tmpdir_name:
            export_library_dir = (Path(tmpdir_name) / "CalibreLibray").absolute()
            export_library_dir.mkdir()

            if calibre_library.exists():
                print(f"[green]✓[/green] Exporting library at {calibre_library} into {export_library_dir}")  # noqa: E501

            subprocess.run(
                [
                    "${pkgs.calibre}/bin/calibredb",  # noqa: E501
                    "export",
                    "--all",
                    f"--to-dir={export_library_dir.as_posix()}",
                ],
                capture_output=True,
                text=True,
                check=True,
            )
            now = datetime.now().strftime("%Y-%m-%d")
            tmpdir = Path(tmpdir_name)
            tarball = (tmpdir / f"CalibreLibrary_on_{now}.tar.bz2").absolute()  # noqa: E501
            print(f"[green]✓[/green] Compressing as {tarball}")
            subprocess.run(
                [
                    "${pkgs.gnutar}/bin/tar",  # noqa: E501
                    "--create",
                    "--bzip2",
                    "--preserve-permissions",
                    "--file",
                    f"{tarball.as_posix()}",
                    f"{export_library_dir.as_posix()}",
                ],
                capture_output=True,
                text=True,
                check=True,
            )
            if Confirm.ask("Upload to mega?"):
                print(f"[green]✓[/green] Uploading {tarball.absolute()} to mega at /calibre_library_backups/{tarball.name}")  # noqa: E501
                subprocess.run(
                    [
                        "${pkgs.megacmd}/bin/mega-put",  # noqa: E501
                        f"{tarball.absolute().as_posix()}",
                        f"/calibre_library_backups/{tarball.name}",  # noqa: E501
                    ],
                    capture_output=True,
                    text=True,
                    check=True,
                )

            else:
                print(f"[green]✓[/green] Completed. Moving tarball to {Path.cwd().absolute()}.")  # noqa: E501
                shutil.move(tarball.as_posix(), ".")

            print(f"[green]✓[/green] Removing all temporary files at {tmpdir.absolute()}")  # noqa: E501


    if __name__ == "__main__":
        cli()
  '';
in {
  options.dotfiles.shell.calibre-utils = {
    enable = lib.mkEnableOption "enable my calibre-utils python scripts cli";
  };
  config = lib.mkIf cfg.enable {
    home.packages = [calibre-utils];
  };
}
