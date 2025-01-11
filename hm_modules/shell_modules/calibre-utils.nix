{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.shell.calibre-utils;
  calibre-utils = pkgs.writers.writePython3Bin "calibre-utils" {libraries = with pkgs.python3Packages; [tabulate typer rich];} ''
    import contextlib
    import re
    import statistics
    import subprocess
    from pathlib import Path
    from typing import Optional
    import typer
    from rich.prompt import Confirm
    from rich import print
    from tabulate import tabulate
    cli = typer.Typer()
    audio = typer.Typer(name="calibre-utils")
    cli.add_typer(audio, name="audio", help="Audio book related commands")
    def get_duration_bitrate(filename: Path) -> Optional[tuple[int, int]]:  # noqa: E302,E501
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
    @audio.command()  # noqa: E302
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
        metadata: list[str] = [";FFMETADATA1"]
        chapter_titles: list[str] = []
        timestamp: int = 0
        bitrates: list[int] = []
        expected_file_sort_prefix = re.compile(r"^\d+ - ")
        for file in files:
            duration_bitrate = get_duration_bitrate(file)
            if duration_bitrate is None:
                return None
            duration, bitrate = duration_bitrate
            bitrates.append(bitrate)
            chapter_title = re.sub(expected_file_sort_prefix, "", file.stem)
            chapter: list[str] = [
                "[CHAPTER]",
                "TIMEBASE=1/1000",
                f"START={timestamp}",
                f"END={timestamp + duration}",
                f"title={chapter_title}",
                ""
            ]
            metadata.extend(chapter)
            chapter_titles.append(chapter_title)
            timestamp += duration
        print(f"[green]✓[/green] Metadata collected from {len(files)} tracks.")
        print(tabulate((
                (i, title, bitrate)
                for i, (title, bitrate)
                in enumerate(zip(chapter_titles, bitrates))
            ),
            headers=["#", "Title", "Bitrate"],
            tablefmt="simple")
        )
        mean_bitrate = int(statistics.mean(bitrates) / 1000)
        # find the closest target bit rate from the mean bitrate
        target_bitrate = min([24, 48, 64, 128, 256, 320], key=lambda n: abs(n-mean_bitrate))  # noqa: E501
        print(f"[green]✓[/green] Target bitrate: {target_bitrate}kbps")
        if not Confirm.ask("[yellow]?[/yellow] Track list and bitrate look good?"):
            print("The files must be sorted in lexographical sort order. prepend the order.")  # noqa: E501
            print("e.g. [cyan]001 - Prologue.mp3[/cyan]")
            print("e.g. [cyan]002 - Chapter 1.mp3[/cyan]")
            print("e.g. [cyan]003 - Chapter 2.mp3[/cyan]")
            raise typer.Exit(2)
        output_file = directory / "chapters.txt"
        try:
            output_file.write_text('\n'.join(metadata))
        except Exception as e:
            print(f"[red]Error writing metadata file: {e}[/red]")
            raise typer.Exit(3)
        input_files = directory / "input_files.txt"
        input_files.write_text("\n".join(f"file '{f.as_posix()}'" for f in files))
        output_file_name = name if name != "notgiven" else directory.absolute().stem  # noqa: E501
        print(f"[green]✓[/green] Merging files to create audio book [cyan]{output_file_name}[/cyan] @ {target_bitrate}kbps...")  # noqa: E501
        ffmpg_cmd = [
            "${pkgs.ffmpeg}/bin/ffmpeg",  # noqa: E501
            "-f",
            "concat",
            "-safe",
            "0",
            "-i",
            "input_files.txt",
            "-i",
            f"{output_file}",
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
    if __name__ == "__main__":  # noqa: E305
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
