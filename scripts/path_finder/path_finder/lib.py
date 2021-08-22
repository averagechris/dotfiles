import os
from dataclasses import dataclass
from pathlib import Path
from typing import Generator, Optional


@dataclass
class PathFinder:
    paths: list[Path]

    @classmethod
    def from_env(cls) -> "PathFinder":
        path = os.getenv("PATH")
        if not path:
            raise RuntimeError("PATH environment variable is not set.")
        return cls(list(map(Path, path.split(":"))))

    def find_first(self, name: str, parent_name: str = "") -> Optional[Path]:
        return next(self.find(name, parent_name=parent_name), None)

    def find(self, name: str, parent_name: str = "") -> Generator[Path, None, None]:
        for path in self.paths:
            if not path.is_dir():
                path = path.parent

            path = path.resolve()

            if parent_name:
                parents = (parent.joinpath(parent_name) for parent in path.parents)
                path = next((parent for parent in parents if parent.exists()), path)

            result_path = path.joinpath(name)

            if result_path.exists():
                yield result_path
