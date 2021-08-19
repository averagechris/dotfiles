from typing import Optional

import typer

from .lib import PathFinder


cli = typer.Typer()


@cli.command()
def main(name: str, find_all: bool = False, parent_name: Optional[str] = None):
    parent_name = parent_name or ""
    path_finder = PathFinder.from_env()

    paths = path_finder.find(name, parent_name=parent_name)

    if not find_all:
        path = next(paths, None)
        paths = [path] if path else []

    for path in paths:
        typer.echo(path)


if __name__ == "__main__":
    cli()
